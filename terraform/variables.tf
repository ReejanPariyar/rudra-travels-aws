variable "aws_region" {
  description = "AWS region for the S3 bucket. Pick whatever's closest to your users — this has no effect on CloudFront itself, which is global."
  type        = string
  default     = "eu-west-2" # London — change to whatever suits your audience
}

variable "domain_name" {
  description = "Your root domain, no protocol, no trailing slash. e.g. \"example.com\""
  type        = string
}
