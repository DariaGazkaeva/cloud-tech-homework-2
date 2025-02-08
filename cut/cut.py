import cv2
import json
import time

PATH_PHOTOS = '/function/storage/photos'
PATH_FACES = '/function/storage/faces'

UNKNOWN_NAME = 'unknown'


def handler(event, context):
    for message in event['messages']:
        body = message['details']['message']['body']
        message = json.loads(body)

        object_id = message['object_id']
        image_path = f'{PATH_PHOTOS}/{object_id}'

        new_object_id = UNKNOWN_NAME + '.' + object_id[:-4] + '.' + str(int(time.time() * 1000000)) + '.' + '.jpg'

        output_path = f'{PATH_FACES}/{new_object_id}'

        load_crop_and_save(image_path, output_path, message['coordinates'])

    return {'statusCode': 200, 'body': ''}


def load_crop_and_save(image_path, output_path, coordinates):
    x, y, x1, y1 = coordinates
    img = cv2.imread(image_path)

    if img is None:
      print(f'Error: Could not open or find the image at {image_path}')
      return
    
    cropped_img = img[y:y1, x:x1]

    if cropped_img.size == 0:
      print('Error: Cropped image has zero size. Check your coordinates.')
      return
    
    cv2.imwrite(output_path, cropped_img)
