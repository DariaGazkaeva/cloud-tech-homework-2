import base64

PATH = "/function/storage/faces"

def handler(event, context):
    object_id = event["params"]["face"]
    image_path = f"{PATH}/{object_id}"
    image_bytes = open(image_path, "rb").read()
    encoded_string = base64.b64encode(image_bytes).decode("utf-8")
    return {
        'statusCode': 200, 
        'headers': {'Content-Type': 'image/jpeg'},
        'body': encoded_string,
        'isBase64Encoded': True
    }
