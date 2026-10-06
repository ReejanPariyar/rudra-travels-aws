# Free SSL certificate for your domain and its www subdomain, validated
# automatically via DNS records Terraform creates in Route 53.
# Must live in us-east-1 for CloudFront to be able to use it — see the
# aws.us_east_1 provider alias in provider.tf.

resource "aws_acm_certificate" "frontend" {
  provider                 = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method          = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "frontend" {
  provider                = aws.us_east_1
  certificate_arn          = aws_acm_certificate.frontend.arn
  validation_record_fqdns  = [for record in aws_route53_record.cert_validation : record.fqdn]
}
