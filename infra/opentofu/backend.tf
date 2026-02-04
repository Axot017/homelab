terraform {
  backend "s3" {
    bucket         = "mateuszledwon-homelab-opentofu-state"
    key            = "homelab/aws/s3.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "mateuszledwon-homelab-opentofu-locks"
    encrypt        = true
  }
}
