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

resource "archive_file" "code_zip" {
  type        = "zip"
  output_path = "func.zip"
  source_dir  = "src"
}

resource "yandex_function" "faces-func" {
  name        = "faces-func"
  description = "function for faces homework"
  user_hash   = archive_file.code_zip.output_sha256
  runtime     = "python37"
  entrypoint  = "main.handler"
  memory      = "128"
  environment = { "TELEGRAM_BOT_TOKEN" = var.tg_bot_key }
  content {
    zip_filename = archive_file.code_zip.output_path
  }
}

resource "yandex_function_iam_binding" "public-faces-func" {
  function_id = yandex_function.faces-func.id
  role        = "serverless.functions.invoker"
  members = [
    "system:allUsers",
  ]
}

output "faces-func-url" {
  value = "https://functions.yandexcloud.net/${yandex_function.faces-func.id}"
}

resource "telegram_bot_webhook" "webhook" {
  url = "https://api.telegram.org/bot${var.tg_bot_key}/setWebhook?url=https://functions.yandexcloud.net/${yandex_function.faces-func.id}"
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

resource "yandex_function" "vvot01-face-detection" {
  name               = "vvot01-face-detection"
  description        = "function for face detection"
  user_hash          = archive_file.code_zip.output_sha256
  runtime            = "python37"
  entrypoint         = "detection.handler"
  memory             = "1024"
  service_account_id = yandex_iam_service_account.sa-hw-2.id
  content {
    zip_filename = archive_file.code_zip.output_path
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
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}
