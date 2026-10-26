provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "primary_bucket" {
  bucket = "homelab-mfe-delivery-bucket"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.primary_bucket.bucket_regional_domain_name
    origin_id   = "S3-Primary"
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

  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }
}
