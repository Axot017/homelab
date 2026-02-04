variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "eu-central-1"
}

variable "backups_bucket_name" {
  type        = string
  description = "S3 bucket name for backups."
  default     = "mateuszledwon-homelab-backups"
}

variable "videos_bucket_name" {
  type        = string
  description = "S3 bucket name for vibe env demo videos."
  default     = "mateuszledwon-homelab-vibe-env-demos"
}

variable "backups_user_name" {
  type        = string
  description = "IAM user name for backup access."
  default     = "homelab-backups"
}

variable "videos_user_name" {
  type        = string
  description = "IAM user name for video upload access."
  default     = "homelab-vibe-env-demos"
}
