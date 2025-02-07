import os
import json
import cv2
import boto3


PATH = '/function/storage/photos'
ENDPOINT_URL = "https://message-queue.api.cloud.yandex.net"
QUEUE_URL = os.environ.get("QUEUE_URL")
REGION_ID = os.environ.get("REGION_ID")
SECRET_KEY = os.environ.get("SECRET_KEY")
ACCESS_KEY = os.environ.get("ACCESS_KEY")

def handler(event, context):
    print('Face detection handler')
    print(event)
    print(context)

    # Каскад Хаара для обнаружения лиц (предобученная модель)
    face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')

    messages = event['messages']
    message_queue = []

    for message in messages:
        object_id = message['details']['object_id']
        image = cv2.imread(f'{PATH}/{object_id}')

        # Преобразуем изображение в оттенки серого (это необходимо для работы каскада Хаара)
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        # Обнаруживаем лица
        faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(30, 30))

        for (x, y, w, h) in faces:
           x, y, w, h = int(x), int(y), int(w), int(h)
           message_queue.append({"object_id": object_id, "coordinates": [x, y, x + w, y + h]})
    
    send_messages_to_queue(message_queue)

    return {'statusCode': 200, 'body': 'test-text'}

def send_messages_to_queue(messages):
    print("Sending messages to queue")
    print(messages)
    sqs_client = boto3.client(
        'sqs', 
        endpoint_url=ENDPOINT_URL, 
        region_name=REGION_ID,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY
    )

    for message in messages:
        message_body = json.dumps(message)
        response = sqs_client.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=message_body
        )
    print(response)
