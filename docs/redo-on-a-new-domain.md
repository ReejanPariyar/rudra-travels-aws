# Do It Again From Scratch

*How to redeploy this exact kind of AWS static-site setup on a brand new domain, using the real, reusable Terraform code from this project.*

**How this fits with the other two documents:** the timeline guide tells you what happened on this specific project; the concepts guide explains the why behind each piece and the real problems hit along the way. This document is the practical "do it yourself, right now, on something new" version — it assumes you have the actual Terraform files (the [`terraform/`](../terraform) folder of this repository) sitting next to your website’s files.

---

## What You End Up With

S3 (file storage) + CloudFront (CDN) + ACM (free SSL) + Route 53 (DNS) — a fast, cheap, secure static site host. No server to patch, no backend to run. If a backend or CMS is needed later, that’s a separate, additional piece — most sites don’t need one, and this setup deliberately doesn’t include one.

## Before You Start

- An AWS account, with the AWS CLI installed and configured (aws sts get-caller-identity should return your account details)
- Terraform installed
- A domain name, bought from any registrar
- Your actual website files (index.html and friends) ready in their own folder, separate from the Terraform files
## The Steps

1. Copy the Terraform code folder to sit **alongside** your website’s folder, not inside it:
```
my-project/
  my-website/                    <- your actual site files
  terraform/      <- the terraform code
```

2. Set your real domain:
```
cd terraform
cp terraform.tfvars.example terraform.tfvars
# then edit terraform.tfvars and put in your real domain name
```

3. Provision the infrastructure:
```
terraform init
terraform plan    # read this before continuing
terraform apply   # type yes when prompted
```

4. Point your domain at AWS. The apply output includes `nameservers_to_set_at_registrar` — four values. Log into wherever you bought your domain, find its nameserver settings, and replace whatever is there with these four. This is the one step with no command-line equivalent — it happens on your registrar’s own website.
5. Wait for DNS to propagate, checking with:
```
dig yourdomain.com NS
```

Once this returns the AWS nameservers cleanly, move on. This can take anywhere from a few minutes to (rarely) 48 hours.

1. Deploy your actual website files:
```
cd ../my-website
../terraform/scripts/deploy-frontend.sh
```

Run this same command every time you update your site.

1. Verify it’s really live:
```
curl -s https://yourdomain.com/
```

## If Something Needs Tearing Down

```
terraform destroy
```

This removes everything Terraform created. Real resources, gone for real — there’s no undo.

## Two Things Worth Doing Before You Rely On This For Anything Real

- **Move Terraform’s state to a remote backend (S3)** rather than leaving terraform.tfstate as a local file. A local state file can be accidentally deleted (this happened during the original project this template comes from) — remote state makes that mistake impossible.
- **Re-read the "Everything That Actually Went Wrong" section** of the concepts guide before you hit the same problems yourself — DNS propagation errors that look scary but aren’t, the S3 "bucket already exists" error after a rebuild, and what to do if your own state file ever goes missing.
## What’s in the Code Package

The [`terraform/`](../terraform) folder of this repository contains:

- `provider.tf` — tells Terraform to talk to AWS, and sets up the special us-east-1 region CloudFront’s certificate needs
- `variables.tf` + `terraform.tfvars.example` — where your domain name and region get set
- `s3-frontend.tf` — the private storage bucket for your site’s files
- `acm.tf` — the free SSL certificate and its automatic DNS validation
- `cloudfront.tf` — the CDN that actually serves your site to visitors
- `route53.tf` — the DNS zone and records
- `outputs.tf` — prints the nameservers, bucket name, and CloudFront domain you need after deploying
- `scripts/deploy-frontend.sh` — the one command you’ll run repeatedly to push site updates
