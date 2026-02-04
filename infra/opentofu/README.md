# OpenTofu AWS S3

This OpenTofu root provisions:

- S3 bucket for homelab backups with cost-optimized lifecycle
- S3 bucket for vibe env demo videos with 7-day expiration
- IAM users with least-privilege access to each bucket

## Manual bootstrap steps (one-time)

### 1) Create the state bucket and DynamoDB lock table

These are required before running `tofu init`.

```bash
aws s3api create-bucket \
  --bucket mateuszledwon-homelab-opentofu-state \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1

aws s3api put-bucket-versioning \
  --bucket mateuszledwon-homelab-opentofu-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket mateuszledwon-homelab-opentofu-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name mateuszledwon-homelab-opentofu-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-central-1
```

### 2) Create GitHub Actions AWS role (OIDC)

This workflow uses GitHub OIDC. Create an IAM role with a trust policy for your repo
and attach permissions that allow S3 + IAM + DynamoDB management and access to the
state bucket/table.

Example trust policy (replace account id and repo):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:Axot017/homelab:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

For simplicity, attach the managed policy `AdministratorAccess` to the role, or
create a custom policy that grants:

- S3 bucket and object permissions for `mateuszledwon-homelab-*`
- IAM user and policy management for the two users
- DynamoDB access to the lock table

Store the role ARN in GitHub Actions secret: `AWS_ROLE_ARN`.

### 3) Create access keys for IAM users (manual)

OpenTofu creates the users but not the credentials. Generate keys manually:

```bash
aws iam create-access-key --user-name homelab-backups
aws iam create-access-key --user-name homelab-vibe-env-demos
```

Store these credentials in your secret manager or Kubernetes secrets.

## Usage

```bash
cd infra/opentofu
tofu init
tofu plan
tofu apply
```
