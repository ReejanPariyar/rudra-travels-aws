output "nameservers_to_set_at_registrar" {
  description = "Log into your domain registrar and set these as your domain's nameservers — this is what actually hands DNS control to AWS"
  value       = aws_route53_zone.main.name_servers
}

output "cloudfront_domain" {
  description = "CloudFront's own domain, useful for testing before DNS has propagated"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_bucket_name" {
  description = "Where scripts/deploy-frontend.sh uploads the site"
  value       = aws_s3_bucket.frontend.bucket
}
