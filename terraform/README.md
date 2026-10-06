# Reusable Static Site on AWS — Terraform Template

> **Read this first.** This folder is a template for a **new** domain. Do not run it against
> `rudra-travels.com`. That site already exists in AWS, and the Terraform state file that
> recorded it was lost, so `terraform apply` from here would try to create everything a second
> time. The live site is deployed with a script that talks to AWS directly. The full story is in
> [docs/concepts-and-problems.md](../docs/concepts-and-problems.md) (Problem 3).


This is the actual, working infrastructure code behind the Rudra Travels
project, stripped of anything project-specific, so you can point it at a
new domain and deploy a new static site from scratch. Pair this with
`complete-timeline-guide.docx` (the command-by-command walkthrough) and
[`docs/concepts-and-problems.md`](../docs/concepts-and-problems.md) (the concepts and problems
explained) — this template is the part those documents describe.

**What this gives you:** S3 (file storage) + CloudFront (CDN) + ACM (free
SSL) + Route 53 (DNS) — a fast, cheap, secure static site host. No server
to patch, no backend to run. If you need a backend or a CMS later, that's
a separate, additional piece — this template deliberately does not
include one, since most sites don't need it.

## Before you start

- An AWS account, with the AWS CLI installed and configured
  (`aws sts get-caller-identity` should return your account details)
- Terraform installed
- A domain name, bought from any registrar
- Your actual website files (`index.html` and friends) ready in their own
  folder, separate from this one

## Steps

1. **Copy this whole folder** to sit alongside your website's folder (not
   inside it):
   ```
   my-project/
     my-website/                    <- your actual site files
     terraform/      <- this folder
   ```

2. **Set your real values:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Edit `terraform.tfvars` and put in your real domain name.

3. **Provision the infrastructure:**
   ```bash
   terraform init
   terraform plan    # read this before continuing
   terraform apply   # type yes when prompted
   ```

4. **Point your domain at AWS.** The apply output includes
   `nameservers_to_set_at_registrar` — four values. Log into wherever you
   bought your domain, find its nameserver settings, and replace whatever
   is there with these four. This is the one step with no command-line
   equivalent — it happens on your registrar's own website.

5. **Wait for DNS to propagate**, checking with:
   ```bash
   dig yourdomain.com NS
   ```
   Once this returns the AWS nameservers cleanly, move on. This can take
   anywhere from a few minutes to (rarely) 48 hours.

6. **Deploy your actual website files:**
   ```bash
   cd ../my-website
   ../terraform/scripts/deploy-frontend.sh
   ```
   Run this same command every time you update your site.

7. **Verify it's really live:**
   ```bash
   curl -s https://yourdomain.com/
   ```

## If something needs tearing down

```bash
terraform destroy
```
This removes everything Terraform created. Real resources, gone for
real — there's no undo.

## Two things worth doing before you rely on this for anything real

- **Move Terraform's state to a remote backend (S3)** rather than leaving
  `terraform.tfstate` as a local file. A local state file can be
  accidentally deleted (this happened during the original project this
  template comes from) — remote state makes that mistake impossible.
- **Read the "Everything That Actually Went Wrong" section** of
  [`docs/concepts-and-problems.md`](../docs/concepts-and-problems.md) before you hit the same
  problems yourself — DNS propagation errors that look scary but aren't,
  the S3 "bucket already exists" error after a rebuild, and what to do if
  your own state file ever goes missing.

## A deploy script that doesn't depend on Terraform's saved state

`scripts/deploy-frontend.sh` asks Terraform for the bucket name, so it stops
working if Terraform's state file is ever lost (this happened on the original
project). `scripts/deploy.sh` finds the bucket and CloudFront distribution by
asking AWS directly which distribution serves your domain, previews what it
will upload or delete, and asks before changing anything:

```bash
cd ../my-website
bash ../terraform/scripts/deploy.sh yourdomain.com
```
