output "backups_bucket_name" {
  value       = aws_s3_bucket.backups.bucket
  description = "S3 bucket name for backups."
}

output "videos_bucket_name" {
  value       = aws_s3_bucket.videos.bucket
  description = "S3 bucket name for demo videos."
}

output "backups_user_name" {
  value       = aws_iam_user.backups.name
  description = "IAM user for backups bucket access."
}

output "videos_user_name" {
  value       = aws_iam_user.videos.name
  description = "IAM user for videos bucket access."
}
