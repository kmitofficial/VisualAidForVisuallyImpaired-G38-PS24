# Deploy with `firebase emulators:start --only functions ` in the backend directory

from firebase_functions import https_fn
from firebase_admin import initialize_app
from dotenv import load_dotenv
import vertexai
import google.generativeai as genai
import vertexai.generative_models as vgenai
import json
import os
import re
import urllib.parse

load_dotenv(".env")  # Load environment variables from .env file
initialize_app() # Initialize Firebase app

# Function to convert a Cloud Storage URL to a gs:// URL
def convert_to_gs_url(url):
    match = re.search(r'/b/([^/]+)/o/([^?]+)', url)
    if match:
        bucket = match.group(1)
        path = urllib.parse.unquote(match.group(2))
        return f"gs://{bucket}/{path}"
    else:
        raise ValueError("Invalid URL format")

#function to query the model with the image and the user query
@https_fn.on_call()
def image(req: https_fn.CallableRequest):
    GOOGLE_API_KEY=os.environ.get('GOOGLE_API_KEY')
    genai.configure(api_key=GOOGLE_API_KEY) # Configure the API key for the Generative AI API
    config = genai.GenerationConfig(max_output_tokens=1024, temperature=0.6, response_mime_type='plain/text')  # Set the generation configuration
    model = genai.GenerativeModel('gemini-1.5-flash') # Initialize the GenerativeModel(gemini-1.5-flash model)
    data = req.data.get('data') # Get the image data from the request
    mime_type = req.data.get('mime_type') # Get the mime type of the image from the request
    
    # Create a Part object with the image data and mime type
    filePart = {
                'mime_type': mime_type,
                'data': data
                }
    
    # Get the user query from the request
    query = req.data.get('query')

    #check if the user query is present or not
    if query:
        textPart = query
    else:
        #re initialize the config to get the response in json format
        config = genai.GenerationConfig(max_output_tokens=1024, temperature=0.6, response_mime_type='application/json') 

        #system prompt to be used when the user query is not present
        textPart = """
        Describe the image in detail. Also provide a suitable title for the image. 
        Answer whether there is anything dangerous with a 'Yes/No' for a visually impaired person in the image. Only if 'Yes', provide the information regarding the danger.
        The answer should only contain the key-value {Danger, Title, Description}. Return only a JSON object
        
        Examples of the response:
        {
            "Danger": "Yes",
            "Title": "Crowded Street with Unmarked Construction Area",
            "Description": "A busy urban street with a lot of pedestrian and vehicular traffic. There is an unmarked construction area with scattered debris and a partially open manhole in the middle of the sidewalk, posing significant risks to visually impaired individuals."
        }

        {
            "Danger": "No",
            "Title": "Cozy Coffee Shop",
            "Description": "An image capturing the cozy atmosphere of a coffee shop. The interior is warmly lit with soft, ambient lighting. There are comfortable seating arrangements, including plush armchairs and wooden tables. A chalkboard on the wall displays the day's specials, and there is a handwritten sign near the entrance that says 'Welcome to Our Happy Place'. Customers are seen chatting and enjoying their drinks, creating a welcoming and inviting environment."
        }

        {
            "Danger": "No",
            "Title": "Peaceful Beach at Sunset",
            "Description": "An image capturing a peaceful beach at sunset. The sky is painted with vibrant hues of orange and pink as the sun sets over the horizon. The beach is mostly empty, with gentle waves lapping at the shore. A few seashells are scattered across the sand, and there are distant silhouettes of seagulls flying."
        }

        {
            "Danger": "Yes",
            "Title": "Busy Train Station Platform",
            "Description": "An image of a crowded train station platform. There are numerous passengers standing near the edge of the platform, waiting for the train. The platform is narrow, and there are no tactile paving strips to guide visually impaired individuals. Additionally, the fast-moving trains and the lack of clear barriers make it a potentially dangerous environment."
        }
        """
    
    response = model.generate_content([textPart, filePart], generation_config=config)
    print(response.candidates[0].content.parts[0].text) # Print the response text

    response_dict = json.loads(response.candidates[0].content.parts[0].text)  # Convert the response text to a json object
    return response_dict # Return the response json object


@https_fn.on_call()
def video(req: https_fn.CallableRequest):
    vertexai.init(project='vision-crafters', location='us-central1') # Initialize Vertex AI

    #Set the generation configuration for plain text response (used if user query is present)
    config = vgenai.GenerationConfig(max_output_tokens=1024, temperature=0.6, response_mime_type='plain/text') 

    model = vgenai.GenerativeModel('gemini-1.5-flash') # Initialize the GenerativeModel(gemini-1.5-flash model)

    data = req.data.get('data') # Get the video data from the request
    mime_type = req.data.get('mime_type') # Get the mime type of the video from the request

    # Create a Part object with the gs:// URL of the video (generated by the convert_to_gs_url function) and the mime type 
    filePart = vgenai.Part.from_uri(convert_to_gs_url(data), mime_type=mime_type)
    print(data)

    print(convert_to_gs_url(data)) # manual check if the gs url is correct by printing it

    query = req.data.get('query') # Get the user query from the request

    #check if the user query is present or not
    if query:
        textPart = query
    else:
        #re initialize the config to get the response in json format as the user query is not present
        config = vgenai.GenerationConfig(max_output_tokens=1024, temperature=0.6, response_mime_type='application/json')

        #system prompt to be used when the user query is not present for video description
        textPart = """
        Describe the video in detail. Also provide a suitable title for the video. 
        Answer whether there is anything dangerous with a Yes/No for a visually impaired person in the video. Only if 'Yes', provide the information regarding the danger.
        The answer should only contain the key-value {Danger, Title, Description}.Return only a JSON object!
        
        Examples of the response:
        {
            "Danger": "Yes",
            "Title": "Busy Intersection with Fast-Moving Traffic",
            "Description": "A video showing a busy city intersection with fast-moving vehicles and numerous pedestrians. Traffic signals are changing frequently, and there are no audible signals for visually impaired individuals. The chaotic environment and lack of clear pathways make it extremely dangerous. One pedestrian is seen narrowly avoiding a car, highlighting the high risk involved."
        }

        {
            "Danger": "No",
            "Title": "Quiet Library Reading Room",
            "Description": "A video of a quiet library reading room. The room is spacious and well-lit with rows of bookshelves and comfortable seating areas. A sign on the wall reads 'Please Keep Silence'. There are large windows letting in natural light, and the environment is calm and orderly, making it an ideal place for studying and reading."
        }

        {
            "Danger": "No",
            "Title": "Family Picnic in a Sunny Park",
            "Description": "A video of a family enjoying a picnic in a sunny park. The area is flat and grassy, with children playing nearby and adults sitting on blankets under the shade of trees. There are picnic tables, a small playground, and a clear pathway leading to restrooms and water fountains. The environment is safe and family-friendly."
        }

        {
            "Danger": "Yes",
            "Title": "Mountain Hiking Trail with Steep Cliffs",
            "Description": "A video showing a narrow mountain hiking trail with steep cliffs on one side. The trail is rugged and uneven, with loose rocks and a steep drop-off. Hikers are seen carefully navigating the path, using trekking poles for stability. The lack of guardrails and the proximity to the cliff edge make it very dangerous for visually impaired individuals."
        }
        """
    
    response = model.generate_content([textPart, filePart], generation_config=config)  # Generate content using the model
    print(response.candidates[0].content.parts[0].text)
    response_dict = json.loads(response.candidates[0].content.parts[0].text) # Convert the response text to a json object
    return response_dict # Return the response json object
