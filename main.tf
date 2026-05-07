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

# -------------------------------
# Primary S3 bucket
# -------------------------------
resource "aws_s3_bucket" "s3_tf" {
  bucket = "osy-ce12m3l2-bucket"
}

resource "aws_s3_bucket_notification" "s3_events" {
  bucket      = aws_s3_bucket.s3_tf.id
  eventbridge = true
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

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
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

# -------------------------------
# Replica bucket
# -------------------------------
resource "aws_s3_bucket" "replica" {
  bucket = "osy-ce12m3l2-replica"
}

resource "aws_s3_bucket_public_access_block" "replica_block" {
  bucket                  = aws_s3_bucket.replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -------------------------------
# Logging bucket
# -------------------------------
resource "aws_s3_bucket" "s3_logs" {
  bucket = "osy-ce12m3l2-logs"
}

resource "aws_s3_bucket_notification" "s3_logs_events" {
  bucket      = aws_s3_bucket.s3_logs.id
  eventbridge = true
}

resource "aws_s3_bucket_public_access_block" "s3_logs_block" {
  bucket                  = aws_s3_bucket.s3_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_logs_lifecycle" {
  bucket = aws_s3_bucket.s3_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_versioning" "replica_versioning" {
  bucket = aws_s3_bucket.replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica_encryption" {
  bucket = aws_s3_bucket.replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_logging" "replica_logging" {
  bucket        = aws_s3_bucket.replica.id
  target_bucket = aws_s3_bucket.s3_logs.id
  target_prefix = "replica-log/"
}

# -------------------------------
# Replication IAM role + policy
# -------------------------------
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
        Effect = "Allow"
        Action = [
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
# -------------------------------
# Primary S3 bucket logging
# -------------------------------
resource "aws_s3_bucket_logging" "s3_tf_logging" {
  bucket        = aws_s3_bucket.s3_tf.id
  target_bucket = aws_s3_bucket.s3_logs.id
  target_prefix = "s3-tf-log/"
}

# -------------------------------
# Replica bucket compliance
# -------------------------------
resource "aws_s3_bucket_notification" "replica_events" {
  bucket      = aws_s3_bucket.replica.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "replica_lifecycle" {
  bucket = aws_s3_bucket.replica.id

  rule {
    id     = "expire-replica-objects"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 60
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -------------------------------
# Logging bucket compliance
# -------------------------------
resource "aws_s3_bucket_versioning" "s3_logs_versioning" {
  bucket = aws_s3_bucket.s3_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_logs_encryption" {
  bucket = aws_s3_bucket.s3_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# -------------------------------
# KMS key with explicit policy
# -------------------------------
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}
# Destination bucket in another region
provider "aws" {
  alias  = "secondary"
  region = "ap-southeast-2"
}

resource "aws_s3_bucket" "s3_logs_replica" {
  provider = aws.secondary
  bucket   = "osy-ce12m3l2-logs-replica"
}

resource "aws_s3_bucket_versioning" "s3_logs_replica_versioning" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.s3_logs_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM role for replication
resource "aws_iam_role" "logs_replication_role" {
  name = "s3-logs-replication-role"

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

resource "aws_iam_role_policy" "logs_replication_policy" {
  role = aws_iam_role.logs_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication"
        ]
        Resource = [aws_s3_bucket.s3_logs.arn, "${aws_s3_bucket.s3_logs.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = [aws_s3_bucket.s3_logs_replica.arn, "${aws_s3_bucket.s3_logs_replica.arn}/*"]
      }
    ]
  })
}

# Replication configuration
resource "aws_s3_bucket_replication_configuration" "s3_logs_replication" {
  bucket = aws_s3_bucket.s3_logs.id
  role   = aws_iam_role.logs_replication_role.arn

  rule {
    id     = "replicate-logs"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.s3_logs_replica.arn
      storage_class = "STANDARD"
    }
  }
}
# -------------------------------
# Cross-region Logging bucket compliance
# -------------------------------
resource "aws_s3_bucket_notification" "s3_logs_replica_events" {
  provider    = aws.secondary
  bucket      = aws_s3_bucket.s3_logs_replica.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_logs_replica_lifecycle" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.s3_logs_replica.id

  rule {
    id     = "expire-replica-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "s3_logs_replica_block" {
  provider                = aws.secondary
  bucket                  = aws_s3_bucket.s3_logs_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_logs_replica_encryption" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.s3_logs_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_logging" "s3_logs_replica_logging" {
  provider      = aws.secondary
  bucket        = aws_s3_bucket.s3_logs_replica.id
  target_bucket = aws_s3_bucket.s3_logs.id
  target_prefix = "s3-logs-replica/"
}
