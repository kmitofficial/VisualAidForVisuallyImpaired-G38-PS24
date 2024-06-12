import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mime/mime.dart';
import 'app_state.dart'; // Import the AppState class
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutterbasics/services/database.dart';
import 'package:path_provider/path_provider.dart';

// Function to get application directory path and create image and video folders
Future<String> _getAppDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  final appDir = directory.path;

  final imageDir = Directory('$appDir/images');
  if (!await imageDir.exists()) {
    await imageDir.create(recursive: false);
  }

  final videoDir = Directory('$appDir/videos');
  if (!await videoDir.exists()) {
    await videoDir.create(recursive: false);
  }

  return appDir;
}

Future<void> pickMedia(BuildContext context, Function(String) addDescription,
    AppState appState) async {
  final ImagePicker _pickerGal = ImagePicker();
  final Database db = await initializeDatabase(); // Initialize the database

  final choice = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Choose Media Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: const Text('Image'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      );
    },
  );

  if (choice != null) {
    XFile? pickedFile;
    if (choice == 'image') {
      pickedFile = await _pickerGal.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxHeight: 1080,
        maxWidth: 1920,
      );
    } else if (choice == 'video') {
      pickedFile = await _pickerGal.pickVideo(source: ImageSource.gallery);
    }

    if (pickedFile != null) {
      final mimeType = lookupMimeType(pickedFile.path);

      if (mimeType != null && mimeType.startsWith('video')) {
        appState.setSpinnerVisibility(true);
        await uploadVideo(File(pickedFile.path), addDescription, appState,
            db); // Pass the db instance
        appState.setSpinnerVisibility(false);
      } else if (mimeType != null && mimeType.startsWith('image')) {
        appState.setSpinnerVisibility(true);
        await uploadImage(File(pickedFile.path), addDescription, appState,
            db); // Pass the db instance
        appState.setSpinnerVisibility(false);
      } else {
        print("Unsupported file type");
      }
    } else {
      print("No file selected");
    }
  }
}

Future<void> getImageCM(BuildContext context, Function(String) addDescription,
    AppState appState) async {
  final ImagePicker _pickerCam = ImagePicker();
  final Database db = await initializeDatabase(); // Initialize the database

  final pickedFile_Camera = await _pickerCam.pickImage(
    source: ImageSource.camera,
    imageQuality: 100,
  );

  if (pickedFile_Camera != null) {
    File imageCam = File(pickedFile_Camera.path);
    appState.setSpinnerVisibility(true);
    await uploadImage(
        imageCam, addDescription, appState, db); // Pass the db instance
    appState.setSpinnerVisibility(false);
  } else {
    print("No image Captured");
  }
}

Future<void> getVideoFile(BuildContext context, Function(String) addDescription,
    AppState appState) async {
  final ImagePicker _pickerCam = ImagePicker();
  final Database db = await initializeDatabase(); // Initialize the database

  appState.setSpinnerVisibility(true);
  final videoFile = await _pickerCam.pickVideo(source: ImageSource.camera);

  if (videoFile != null) {
    final storageRef = FirebaseStorage.instance.ref();
    final uniqueId = Uuid().v1();
    final fileRef = storageRef.child('$uniqueId.mp4');

    await fileRef.putFile(File(videoFile.path));

    final videoUrl = await fileRef.getDownloadURL();

    final response = await FirebaseFunctions.instance
        .httpsCallable('video')
        .call({'data': videoUrl, 'mime_type': 'video/mp4'});

    final data = response.data;

    final description_Video_camera =
        ('Danger: ${data["Danger"]}\nTitle: ${data["Title"]}\nDescription: ${data["Description"]}');

    addDescription(description_Video_camera);

    print(
        'Danger: ${data["Danger"]}\nTitle: ${data["Title"]}\nDescription: ${data["Description"]}');

    await insertVideo(db, uniqueId, videoFile.path, 'video/mp4');
  }

  appState.setSpinnerVisibility(false);
}

Future<void> uploadImage(File? imageFile, Function(String) addDescription,
    AppState appState, Database db) async {
  if (imageFile == null) return;

  appState.setSpinnerVisibility(true);

  final bytes = await imageFile.readAsBytes();
  final uniqueImageId = Uuid().v1();
  final base64Image = base64Encode(bytes);
  final mimeType = lookupMimeType(imageFile.path);

  if (mimeType == null) {
    print('Unsupported file format');
    appState.setSpinnerVisibility(false);
    return;
  }

  final response = await FirebaseFunctions.instance
      .httpsCallable('image')
      .call(<String, dynamic>{
    'data': base64Image,
    'mime_type': mimeType,
  });

  if (response.data != null) {
    final description =
        'Danger: ${response.data["Danger"]}\nTitle: ${response.data["Title"]}\nDescription: ${response.data["Description"]}';

    addDescription(description);

    print(description);
    final data = response.data;
    print(data);
    print(
        'Danger: ${data["Danger"]}\nTitle: ${data["Title"]}\nDescription: ${data["Description"]}');

    final appDir = await _getAppDirectory();
    final newFilePath =
        '$appDir/images/$uniqueImageId.${imageFile.path.split('.').last}';
    final newFile = await imageFile.copy(newFilePath);
    print('ID Type: ${uniqueImageId.runtimeType}');
    print("Mime Type: ${mimeType.runtimeType}");
    print("File Path: ${newFilePath.runtimeType}"); // Debug print

    await insertImage(db, uniqueImageId, newFilePath, mimeType);
  } else {
    print("Failed to upload");
  }

  appState.setSpinnerVisibility(false);
}

Future<void> uploadVideo(File videoFile, Function(String) addDescription,
    AppState appState, Database db) async {
  final storageRef = FirebaseStorage.instance.ref();
  final uniqueId = Uuid().v1();
  final fileRef = storageRef.child('$uniqueId.mp4');

  await fileRef.putFile(videoFile);

  final videoUrl = await fileRef.getDownloadURL();

  final response = await FirebaseFunctions.instance
      .httpsCallable('video')
      .call({'data': videoUrl, 'mime_type': 'video/mp4'});

  final data = response.data;

  final description_Vid =
      'Danger: ${data["Danger"]}\nTitle: ${data["Title"]}\nDescription: ${data["Description"]}';

  addDescription(description_Vid);

  print(
      'Danger: ${data["Danger"]}\nTitle: ${data["Title"]}\nDescription: ${data["Description"]}');

  final appDir = await _getAppDirectory();
  final newFile = await videoFile.copy('$appDir/videos/$uniqueId.mp4');

  await insertVideo(db, uniqueId, newFile.path, 'video/mp4');

  appState.setSpinnerVisibility(false);
}
