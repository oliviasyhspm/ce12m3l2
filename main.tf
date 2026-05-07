provider "aws" {
  region = "ap-southeast-1"
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "sctp-ce12-tfstate-bucket"
    key    = "osy-ce12m3l2.tfstate"
    region = "ap-southeast-1"
  }
}

# Primary S3 bucket
resource "aws_s3_bucket" "s3_tf" {
  bucket = "osy-ce12m3l2-bucket"
}

# Event notifications (EventBridge)
resource "aws_s3_bucket_notification" "s3_events" {
  bucket      = aws_s3_bucket.s3_tf.id
  eventbridge = true
}

# Public access block
resource "aws_s3_bucket_public_access_block" "s3_block" {
  bucket                  = aws_s3_bucket.s3_tf.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "s3_lifecycle" {
  bucket = aws_s3_bucket.s3_tf.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {
      prefix = "" # applies to all objects
    }

    expiration {
      days = 30
    }
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.s3_tf.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.s3_tf.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
}

# Logging target bucket
resource "aws_s3_bucket" "s3_logs" {
  bucket = "osy-ce12m3l2-logs"
}

# Attach logging to main bucket
resource "aws_s3_bucket_logging" "s3_logging" {
  bucket        = aws_s3_bucket.s3_tf.id
  target_bucket = aws_s3_bucket.s3_logs.id
  target_prefix = "log/"
}

# Destination bucket in another region for replication
provider "aws" {
  alias  = "replica"
  region = "ap-northeast-1"
}

resource "aws_s3_bucket" "replica" {
  provider = aws.replica
  bucket   = "osy-ce12m3l2-replica"
}

# IAM role for replication
resource "aws_iam_role" "replication_role" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "replication_policy" {
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication"
        ]
        Resource = [aws_s3_bucket.s3_tf.arn, "${aws_s3_bucket.s3_tf.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = [aws_s3_bucket.replica.arn, "${aws_s3_bucket.replica.arn}/*"]
      }
    ]
  })
}

# Replication configuration
resource "aws_s3_bucket_replication_configuration" "s3_replication" {
  bucket = aws_s3_bucket.s3_tf.id
  role   = aws_iam_role.replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"
    }
  }
}
