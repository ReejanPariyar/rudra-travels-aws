# Creates a Route 53 hosted zone for the domain. This does NOT
# automatically move your domain's DNS management here — after this is
# applied, Terraform will output a set of nameservers. You then need to
# log into wherever you bought the domain and update its nameservers to
# these ones. That's the step that actually hands DNS control over to
# AWS. See README.md.

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# yourdomain.com and www.yourdomain.com -> CloudFront (frontend)
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# Optional: if you ever need to verify domain ownership with an outside
# service (Google Search Console, another mail provider, etc.), add a
# TXT record here rather than at your registrar — since AWS controls
# DNS now, not the registrar. Uncomment and fill in the real value:
#
# resource "aws_route53_record" "domain_verification" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = var.domain_name
#   type    = "TXT"
#   ttl     = 300
#   records = ["paste-the-verification-value-here"]
# }
