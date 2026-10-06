terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state for now — fine while it's just you working on this.
  # There's a ready-to-go remote state + least-privilege IAM setup in
  # ../terraform-bootstrap/ whenever you want to level this up — no rush,
  # do it once the simple version is actually live and working.
}

# Main region — pick whatever's closest to your users.
provider "aws" {
  region = var.aws_region
}

# CloudFront requires its ACM certificate to be requested in us-east-1
# specifically, regardless of which region everything else lives in —
# this is a genuine, well-known AWS quirk, not a mistake below.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
