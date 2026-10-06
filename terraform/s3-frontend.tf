# Your site's built files (a plain HTML/CSS/JS folder, or a framework's
# build output) get uploaded here. The bucket itself is private — nobody
# can reach it directly. CloudFront is the only thing allowed to read
# from it (via Origin Access Control below), which is the current
# recommended pattern (replacing the older, now-deprecated Origin Access
# Identity).

resource "aws_s3_bucket" "frontend" {
  bucket = "${replace(var.domain_name, ".", "-")}-frontend"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    # If you're building a single-page app (React, Vue, etc.), unknown
    # paths need to fall back to index.html so client-side routing can
    # take over. Harmless to leave as-is for a plain multi-page site too.
    key = "index.html"
  }
}

data "aws_iam_policy_document" "frontend_bucket_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket_policy.json
}
