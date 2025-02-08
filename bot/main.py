import os
import json
import requests
import random

"""Telegram Bot on Yandex Cloud Function."""

FUNC_RESPONSE = {
    'statusCode': 200,
    'body': ''
}

UNKNOWN_NAME = 'unknown'

PATH_PHOTOS = '/function/storage/photos'
PATH_FACES = '/function/storage/faces'

TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN')
API_GATEWAY_HOST = os.environ.get('API_GATEWAY_HOST')
TELEGRAM_API_URL = f'https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}'

WELCOME_MESSAGE = 'Бот для домашнего задания "Обработка фотографий с лицами людей"'

GLOBAL_COMMANDS = ['/start', '/help']

sent_group_error = {}

def send_message(text, message):
    message_id = message['message_id']
    chat_id = message['chat']['id']
    reply_message = {'chat_id': chat_id,
                     'text': text,
                     'reply_to_message_id': message_id}
    requests.post(url=f'{TELEGRAM_API_URL}/sendMessage', json=reply_message)

def send_face(face, message):
    message_id = message['message_id']
    chat_id = message['chat']['id']

    url = f'https://{API_GATEWAY_HOST}/?face={face}'

    reply_message = {'chat_id': chat_id,
                     'photo': url,
                     'reply_to_message_id': message_id}
    response = requests.post(url=f'{TELEGRAM_API_URL}/sendPhoto', json=reply_message)
    
    print(response.content)

    if not response.ok:
        send_message('Ошибка во время отправки фотографии', message)
        return
    
    response_body = response.json()
    file_unique_id = response_body['result']['photo'][0]['file_unique_id']
    print(file_unique_id)
    face_split = face.split('.')
    if len(face_split) != 5:
        send_message('Ошибка на сервере', message)
        return
    face_name, photo_name, timestamp, tg_file_unique_name, jpg = face_split
    new_face_name = '.'.join([face_name, photo_name, timestamp, file_unique_id, jpg])
    os.rename(f'{PATH_FACES}/{face}', f'{PATH_FACES}/{new_face_name}')


def send_photo(photo, message):
    message_id = message['message_id']
    chat_id = message['chat']['id']

    url = f'https://{API_GATEWAY_HOST}/photo?photo={photo}'

    reply_message = {'chat_id': chat_id,
                     'photo': url,
                     'reply_to_message_id': message_id}
    response = requests.post(url=f'{TELEGRAM_API_URL}/sendPhoto', json=reply_message)
    
    print(response.content)


def handler(event, context):
    if TELEGRAM_BOT_TOKEN is None:
        return FUNC_RESPONSE
    
    update = json.loads(event['body'])

    if 'message' not in update:
        return FUNC_RESPONSE
    
    message_in = update['message']

    if 'text' not in message_in:
        send_message('Ошибка', message_in)
        return FUNC_RESPONSE
    
    text = message_in['text']

    if 'reply_to_message' in message_in:
        bot_message = message_in['reply_to_message']
        is_bot_message = bot_message['from']['is_bot']
        if not is_bot_message:
            send_message('Вы ответили на собственное сообщение', message_in)
            return FUNC_RESPONSE
        if 'photo' not in bot_message:
            send_message('Вы ответили на сообщение без фото', message_in)
            return FUNC_RESPONSE
        if not is_valid_name(text):
            send_message(f'{text} не является валидным именем', message_in)
            return FUNC_RESPONSE
        file_unique_id = bot_message['photo'][0]['file_unique_id']
        faces = os.listdir(PATH_FACES)
        for face in faces:
            face_split = face.split('.')
            if len(face_split) != 5:
                send_message('Ошибка на сервере', message_in)
                return FUNC_RESPONSE
            face_name, photo_name, timestamp, tg_file_unique_name, jpg = face_split
            if file_unique_id == tg_file_unique_name:
                new_face_name = '.'.join([text, photo_name, timestamp, tg_file_unique_name, jpg])
                os.rename(f'{PATH_FACES}/{face}', f'{PATH_FACES}/{new_face_name}')
                send_message(f'Успешно сохранили фото с именем {text}', message_in)
                return FUNC_RESPONSE

    if text in GLOBAL_COMMANDS:
        send_message(WELCOME_MESSAGE, message_in)
    elif text.startswith('/find'):
        name = text[5:].strip() # remove '/find' = 5 chars
        if not is_valid_name(name):
            send_message(f'Вы ищете невалидное имя {name}', message_in)
            return FUNC_RESPONSE
        faces = os.listdir(PATH_FACES)
        photos = set()
        for face in faces:
            if face.startswith(name + '.'):
                photo_name = face.split('.')[1]
                photos.add(photo_name + '.jpg')
        for photo in photos:
            send_photo(photo, message_in)
        if len(photos) == 0:
            send_message(f'Фотографии с {name} не найдены', message_in)
        
    elif text.startswith('/getface'):
        faces = os.listdir(PATH_FACES)
        unknown_faces = []
        for face in faces:
            if face.startswith(UNKNOWN_NAME + '.'):
                unknown_faces.append(face)
        if len(unknown_faces) == 0:
            send_message('Нет неразмеченных фотографий', message_in)
        else:
            face = random.choice(unknown_faces)
            send_face(face, message_in)
    else:
        send_message('Ошибка', message_in)
    return FUNC_RESPONSE


def is_valid_name(name):
    if '.' in name or '/' in name:
        return False
    return name != UNKNOWN_NAME
