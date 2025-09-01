variable "bucket_name" { type = string }

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = var.bucket_name
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_sse" {
  bucket = var.bucket_name
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state_pab" {
  bucket                  = var.bucket_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
