terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    telegram = {
      source = "yi-jiayu/telegram"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone                     = "ru-central1-d"
  service_account_key_file = pathexpand("~/.yc-keys/key.json")
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
}

provider "telegram" {
  bot_token = var.tg_bot_key
}

variable "cloud_id" {
  type        = string
  description = "Cloud id"
}

variable "folder_id" {
  type        = string
  description = "Folder id"
}

variable "tg_bot_key" {
  type        = string
  description = "Telegram bot key"
}

resource "yandex_iam_service_account" "sa-hw-2" {
  name        = "sa-hw-2"
  description = "service account for faces homework"
}

resource "archive_file" "bot_zip" {
  type        = "zip"
  output_path = "bot.zip"
  source_dir  = "bot"
}

resource "yandex_function" "vvot01-boot" {
  name               = "vvot01-boot"
  description        = "function for bot in faces homework"
  user_hash          = archive_file.bot_zip.output_sha256
  runtime            = "python312"
  entrypoint         = "main.handler"
  memory             = "128"
  service_account_id = yandex_iam_service_account.sa-hw-2.id
  environment = {
    "TELEGRAM_BOT_TOKEN" = var.tg_bot_key
    "API_GATEWAY_HOST"   = yandex_api_gateway.vvot01-apigw.domain
  }
  content {
    zip_filename = archive_file.bot_zip.output_path
  }
  mounts {
    name = "photos"
    mode = "rw"
    object_storage {
      bucket = yandex_storage_bucket.vvot01-photo.bucket
    }
  }
  mounts {
    name = "faces"
    mode = "rw"
    object_storage {
      bucket = yandex_storage_bucket.vvot01-faces.bucket
    }
  }
}

resource "yandex_function_iam_binding" "public-vvot01-boot" {
  function_id = yandex_function.vvot01-boot.id
  role        = "serverless.functions.invoker"
  members = [
    "system:allUsers",
  ]
}

resource "telegram_bot_webhook" "webhook" {
  url = "https://api.telegram.org/bot${var.tg_bot_key}/setWebhook?url=https://functions.yandexcloud.net/${yandex_function.vvot01-boot.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-hw-2.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa-hw-2.id
  description        = "static access key"
}

resource "yandex_storage_bucket" "vvot01-photo" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "vvot01-photo"
}

resource "yandex_storage_bucket" "vvot01-faces" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "vvot01-faces"
}

resource "archive_file" "detection_zip" {
  type        = "zip"
  output_path = "detection.zip"
  source_dir  = "detection"
}

resource "yandex_function" "vvot01-face-detection" {
  name               = "vvot01-face-detection"
  description        = "function for face detection"
  user_hash          = archive_file.detection_zip.output_sha256
  runtime            = "python312"
  entrypoint         = "detection.handler"
  memory             = "1024"
  execution_timeout  = "15"
  service_account_id = yandex_iam_service_account.sa-hw-2.id
  environment = {
    QUEUE_URL  = yandex_message_queue.vvot01-task.id,
    REGION_ID  = yandex_message_queue.vvot01-task.region_id,
    ACCESS_KEY = yandex_iam_service_account_static_access_key.sa-static-key.access_key,
    SECRET_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  }
  content {
    zip_filename = archive_file.detection_zip.output_path
  }
  mounts {
    name = "photos"
    mode = "rw"
    object_storage {
      bucket = yandex_storage_bucket.vvot01-photo.bucket
    }
  }
}

resource "yandex_function_iam_binding" "binding-face-detection" {
  function_id = yandex_function.vvot01-face-detection.id
  role        = "serverless.functions.invoker"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa-hw-2.id}",
  ]
}

resource "yandex_function_trigger" "vvot01-photo" {
  name        = "vvot01-photo"
  description = "trigger for face detection"
  function {
    id                 = yandex_function.vvot01-face-detection.id
    service_account_id = yandex_iam_service_account.sa-hw-2.id
  }
  object_storage {
    bucket_id    = yandex_storage_bucket.vvot01-photo.id
    suffix       = ".jpg"
    create       = true
    update       = false
    delete       = false
    batch_cutoff = 1
  }
}

resource "yandex_resourcemanager_folder_iam_member" "sa-editor-queue" {
  folder_id = var.folder_id
  role      = "ymq.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa-hw-2.id}"
}

resource "yandex_message_queue" "vvot01-task" {
  name       = "vvot01-task"
  region_id  = "ru-central1"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}

resource "archive_file" "cut_zip" {
  type        = "zip"
  output_path = "cut.zip"
  source_dir  = "cut"
}

resource "yandex_function" "vvot01-face-cut" {
  name               = "vvot01-face-cut"
  description        = "function for face cut"
  user_hash          = archive_file.cut_zip.output_sha256
  runtime            = "python312"
  entrypoint         = "cut.handler"
  memory             = "512"
  execution_timeout  = "5"
  service_account_id = yandex_iam_service_account.sa-hw-2.id
  content {
    zip_filename = archive_file.cut_zip.output_path
  }
  mounts {
    name = "photos"
    mode = "rw"
    object_storage {
      bucket = yandex_storage_bucket.vvot01-photo.bucket
    }
  }
  mounts {
    name = "faces"
    mode = "rw"
    object_storage {
      bucket = yandex_storage_bucket.vvot01-faces.bucket
    }
  }
}

resource "yandex_function_iam_binding" "binding-face-cut" {
  function_id = yandex_function.vvot01-face-cut.id
  role        = "serverless.functions.invoker"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa-hw-2.id}",
  ]
}

resource "yandex_function_trigger" "vvot01-task" {
  name        = "vvot01-task"
  description = "trigger for face cut from queue"
  function {
    id                 = yandex_function.vvot01-face-cut.id
    service_account_id = yandex_iam_service_account.sa-hw-2.id
  }
  message_queue {
    queue_id           = yandex_message_queue.vvot01-task.arn
    service_account_id = yandex_iam_service_account.sa-hw-2.id
    batch_cutoff       = "1"
    batch_size         = "1"
  }
}

resource "archive_file" "gateway_zip" {
  type        = "zip"
  output_path = "gateway.zip"
  source_dir  = "gateway"
}

resource "yandex_function" "vvot01-gateway" {
  name               = "vvot01-gateway"
  description        = "function for face gateway"
  user_hash          = archive_file.gateway_zip.output_sha256
  runtime            = "python312"
  entrypoint         = "gateway.handler"
  memory             = "512"
  execution_timeout  = "5"
  service_account_id = yandex_iam_service_account.sa-hw-2.id
  content {
    zip_filename = archive_file.gateway_zip.output_path
  }
  mounts {
    name = "faces"
    mode = "rw"
    object_storage {
      bucket = yandex_storage_bucket.vvot01-faces.bucket
    }
  }
}

resource "yandex_function_iam_binding" "binding-gateway" {
  function_id = yandex_function.vvot01-gateway.id
  role        = "serverless.functions.invoker"
  members = [
    "serviceAccount:${yandex_iam_service_account.sa-hw-2.id}",
  ]
}


resource "yandex_api_gateway" "vvot01-apigw" {
  name              = "vvot01-apigw"
  execution_timeout = "300"
  spec              = <<-EOT
openapi: "3.0.0"
info:
  version: 1.0.0
  title: API for photo
paths:
  /:
    get:
      parameters:
        - name: face
          in: query
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Face image
          content:
            'image/jpeg':
              schema:
                type: "string"
      x-yc-apigateway-integration:
        type: cloud_functions
        function_id: ${yandex_function.vvot01-gateway.id}
        tag: "$latest"
        service_account_id: ${yandex_iam_service_account.sa-hw-2.id}
  /photo:
    get:
      parameters:
        - name: photo
          in: query
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Photo
          content:
            'image/jpeg':
              schema:
                type: "string"
      x-yc-apigateway-integration:
        type: object_storage
        bucket: ${yandex_storage_bucket.vvot01-photo.bucket}
        service_account_id: ${yandex_iam_service_account.sa-hw-2.id}
        object: '{photo}'
EOT
}
