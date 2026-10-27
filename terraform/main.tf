terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "primary_bucket" {
  bucket = "homelab-mfe-delivery-bucket"
}

# The bucket is private; only CloudFront (via the OAC below) may read it.
resource "aws_s3_bucket_public_access_block" "primary_bucket" {
  bucket                  = aws_s3_bucket.primary_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Without this, CloudFront has no credentials for the private bucket and every
# request returns 403.
resource "aws_cloudfront_origin_access_control" "cdn" {
  name                              = "homelab-mfe-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.primary_bucket.bucket_regional_domain_name
    origin_id                = "S3-Primary"
    origin_access_control_id = aws_cloudfront_origin_access_control.cdn.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-Primary"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/artifacts/*"
    target_origin_id       = "S3-Primary"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    min_ttl                = 31536000
    default_ttl            = 31536000
    max_ttl                = 31536000
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate { cloudfront_default_certificate = true }
}

# Allow reads from THIS distribution only (not any CloudFront distribution).
data "aws_iam_policy_document" "cdn_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.primary_bucket.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "primary_bucket" {
  bucket = aws_s3_bucket.primary_bucket.id
  policy = data.aws_iam_policy_document.cdn_read.json

  depends_on = [aws_s3_bucket_public_access_block.primary_bucket]
}

output "cdn_domain" {
  description = "Where the micro-frontends are served from"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "bucket" {
  description = "Delivery bucket Jenkinsfile.cd publishes to (S3_BUCKET)"
  value       = aws_s3_bucket.primary_bucket.id
}
