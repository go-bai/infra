# 自定义环境仓库
resource "google_artifact_registry_repository" "custom_environments_repository" {
  format        = "DOCKER" # 使用 docker 格式, 还支持 maven, npm, Go, Apt 等
  repository_id = "${var.prefix}custom-environments"
  labels        = var.labels
}

# 为自定义环境仓库添加 IAM 成员, 允许使用 serviceAccount 访问
resource "google_artifact_registry_repository_iam_member" "custom_environments_repository_member" {
  repository = google_artifact_registry_repository.custom_environments_repository.name
  role       = "roles/artifactregistry.repoAdmin"
  member     = "serviceAccount:${var.google_service_account_email}"
}

# 存储 postgres 连接字符串
resource "google_secret_manager_secret" "postgres_connection_string" {
  secret_id = "${var.prefix}postgres-connection-string"

  replication {
    auto {}
  }
}

# 存储 supabase jwt 密钥
resource "google_secret_manager_secret" "supabase_jwt_secrets" {
  secret_id = "${var.prefix}supabase-jwt-secrets"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "supabase_jwt_secrets" {
  secret      = google_secret_manager_secret.supabase_jwt_secrets.name
  secret_data = " "

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# 存储 redis 连接字符串
resource "google_secret_manager_secret" "redis_url" {
  secret_id = "${var.prefix}redis-url"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_url" {
  secret      = google_secret_manager_secret.redis_url.name
  secret_data = "redis.service.consul"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# 存储 posthog api 密钥
resource "google_secret_manager_secret" "posthog_api_key" {
  secret_id = "${var.prefix}posthog-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "posthog_api_key" {
  secret      = google_secret_manager_secret.posthog_api_key.name
  secret_data = " "

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# terraform 内置的随机密码生成器
resource "random_password" "api_secret" {
  length  = 32
  special = false
}

# 存储 api 密钥
resource "google_secret_manager_secret" "api_secret" {
  secret_id = "${var.prefix}api-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_secret_value" {
  secret = google_secret_manager_secret.api_secret.id

  secret_data = random_password.api_secret.result
}

# 生成 api 管理员密钥
resource "random_password" "api_admin_secret" {
  length  = 32
  special = true
}

# 存储 api 管理员密钥
resource "google_secret_manager_secret" "api_admin_token" {
  secret_id = "${var.prefix}api-admin-token"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_admin_token_value" {
  secret      = google_secret_manager_secret.api_admin_token.id
  secret_data = random_password.api_admin_secret.result
}

# 生成 sandbox 访问令牌哈希种子
resource "random_password" "sandbox_access_token_hash_seed" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "sandbox_access_token_hash_seed" {
  secret_id = "${var.prefix}sandbox-access-token-hash-seed"
  replication {
    auto {}
  }
}

# 存储 sandbox 访问令牌哈希种子
resource "google_secret_manager_secret_version" "sandbox_access_token_hash_seed" {
  secret      = google_secret_manager_secret.sandbox_access_token_hash_seed.id
  secret_data = random_password.sandbox_access_token_hash_seed.result
}
