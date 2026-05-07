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
}

terraform {
  backend "s3" {
    bucket = "sctp-ce12-tfstate-bucket" # Change this
    key    = "osy-ce12m3l2.tfstate"     # Change this
    region = "ap-southeast-1"
  }
}

resource "aws_s3_bucket" "s3_tf" {
  bucket_prefix = "osy-ce12m3l2-bucket" # Set your bucket name here
}

resource "aws_s3_bucket_notification" "s3_events" {
  bucket = aws_s3_bucket.s3_tf.id

  eventbridge {
    events = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket_public_access_block" "s3_block" {
  bucket                  = aws_s3_bucket.s3_tf.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_lifecycle" {
  bucket = aws_s3_bucket.s3_tf.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

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

resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.s3_tf.id

  versioning_configuration {
    status = "Enabled"
  }
}

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
  bucket_prefix = "osy-ce12m3l2-logs"
}

# Attach logging to your main bucket
resource "aws_s3_bucket_logging" "s3_logging" {
  bucket = aws_s3_bucket.s3_tf.id

  target_bucket = aws_s3_bucket.s3_logs.id
  target_prefix = "log/"
}



