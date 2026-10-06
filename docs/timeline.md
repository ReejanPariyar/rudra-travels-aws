# The Complete Timeline

*Every command, in the real order it happened, from an empty AWS account to a live website — what was run, why, how it works, and when in the project it happened.*

This is a chronological runbook, not a tidied-up summary. Real projects don’t go in a straight line — this one didn’t either. It includes a full pivot partway through (a complex app got simplified to a static site), a complete infrastructure reset, and a real mistake that had to be recovered from. All of that is in here, in the order it actually happened.

---

## Stage 0: Before Any AWS Command — Confirming the Tools Work

Before touching real infrastructure, the local machine needs three things confirmed: the AWS CLI is installed and connected to a real account, Terraform is installed, and there’s an SSH key available (needed later for server access).

```
aws --version
terraform --version
aws sts get-caller-identity
ls ~/.ssh/id_ed25519.pub
cat ~/.ssh/id_ed25519.pub
```

**Why:** aws sts get-caller-identity is the standard "am I actually logged in, and as who" check — it returns your AWS account ID and user ARN if the CLI is correctly configured, or a clear error if not. Checking this first avoids a confusing failure five steps later.

**When:** The very first thing done, before any infrastructure existed.

## Stage 1: Defining the Infrastructure as Code

Every AWS resource this project needed was written as Terraform configuration (.tf files) rather than clicked together in the AWS Console. Sensitive or environment-specific values (the domain name, AWS region, SSH key, an IP address to allow SSH from) were kept out of the main code and supplied separately:

```
cat > terraform.tfvars << 'EOF'
domain_name       = "rudra-travels.com"
aws_region        = "eu-west-2"
ssh_public_key    = "ssh-ed25519 AAAA... your-key-here"
allowed_ssh_cidr  = "your.ip.here/32"
EOF
curl ifconfig.me   # used to find the real IP for allowed_ssh_cidr
```

**Why:** Hardcoding an IP address or key directly into shared code is bad practice — tfvars keeps machine- and person-specific values in one file that’s easy to change without touching the actual infrastructure definitions.

**When:** Once, at the very start of the project.

## Stage 2: The First Real Build — terraform init / plan / apply

```
terraform init
terraform plan
terraform apply
```

**How it works:** init downloads the AWS provider plugin Terraform needs to talk to AWS’s API. plan is a dry run — it shows exactly what would be created without doing it, and should always be read before continuing. apply is the real thing: it creates the actual AWS resources and asks for a typed "yes" to confirm.

The very first version of this infrastructure was more complex than what exists today — alongside the S3 bucket, CloudFront distribution, ACM certificate and Route 53 zone that still exist now, it also originally included an EC2 instance (running a Node.js backend) and a Lightsail instance (running WordPress). Both were fully built, tested, and later deliberately removed once the site’s design was simplified (see Stage 6).

**When:** The true starting point of real infrastructure existing in AWS.

## Stage 3: Pointing the Real Domain at AWS

Buying a domain at a registrar (names.co.uk) and having AWS control its DNS are two separate things. Terraform’s output included four AWS nameservers that needed to be manually entered at the registrar.

```
aws route53 list-hosted-zones-by-name --dns-name rudra-travels.com --query "HostedZones[0].Id" --output text
aws route53 get-hosted-zone --id <ZONE_ID> --query "DelegationSet.NameServers" --output table
```

Those four values were then entered manually into names.co.uk’s "Change Nameservers" page — the one step in this entire project that has no command-line equivalent, since it happens on the registrar’s own website.

**Why:** DNS is how the internet turns a name like rudra-travels.com into a technical address. Until the registrar is told "ask AWS," nobody typing the domain reaches anything AWS-hosted, no matter how correctly the AWS side is configured.

**How it works:** Verifying propagation:

```
dig rudra-travels.com NS
```

This was checked repeatedly until it returned the AWS nameservers cleanly. A SERVFAIL/REFUSED error seen partway through looked alarming but was completely normal — different DNS resolvers around the internet update at different speeds during propagation; it wasn’t a sign anything was broken.

**When:** Immediately after the first successful terraform apply, and again later after Stage 8’s full reset (a torn-down and recreated Route 53 zone gets new nameservers, so this step repeats any time that happens).

## Stage 4: Deploying the Original Application (Frontend + Backend)

In its first version, the site was a full React frontend with a separate Node.js/Express backend API, plus a WordPress CMS on Lightsail. Deploying each piece looked like this:

### Frontend

```
npm install
../rudra-infra/scripts/deploy-frontend.sh
```

### Backend (via SSH onto the EC2 instance)

```
ssh ubuntu@<backend_public_ip>
nano /home/ubuntu/rtt-backend/.env
cat /home/ubuntu/rtt-backend/.env
exit
../rudra-infra/scripts/deploy-backend.sh
```

**Why:** Environment variables containing secrets (API keys, JWT secrets) were typed directly on the server via nano rather than copied over the network — safer, since it avoids that sensitive data ever sitting in a file transfer or shell history on the local machine.

### SSL for the backend’s own subdomain

```
ssh ubuntu@<backend_public_ip> "sudo certbot --nginx -d api.rudra-travels.com --non-interactive --agree-tos -m you@example.com --redirect"
```

**Why:** The frontend has its own certificate via ACM/CloudFront; the backend, running on a plain EC2 instance, needed its own separately-issued certificate (via Let’s Encrypt, through certbot) for its own subdomain.

**When:** After Stage 3, once DNS was resolving — certbot can’t issue a certificate for a domain that doesn’t already point at the server.

## Stage 5: Verifying a Deploy Actually Took Effect

```
curl -s https://rudra-travels.com/ | grep -o 'index-[a-zA-Z0-9-]*\.js'
curl -s https://rudra-travels.com/assets/<filename>.js | grep -c "some-recent-change"
```

**Why:** curl talks to the live server directly, bypassing any browser cache — the fastest way to confirm what’s actually being served, separate from what a browser happens to be showing on screen.

**When:** Used repeatedly throughout the whole project, any time a deploy’s effect needed confirming.

## Stage 6: The Pivot — Deciding to Simplify

After the full version (accounts, checkout, three payment gateways, WordPress CMS) was working, a closer look at the real regulatory and trust implications of taking online payments for a small overseas business led to a deliberate decision: replace it with a simpler static site and a direct enquiry-based booking flow. This wasn’t a step backward from a technical failure — it was a judgement call once the actual business constraints were understood.

No new commands were needed for this decision itself — the next stages cover unwinding the old infrastructure and deploying the replacement.

## Stage 7: Tearing Down the No-Longer-Needed Infrastructure

```
terraform destroy
```

This removed the EC2 instance, its security group and Elastic IP, and the Lightsail WordPress instance and its static IP — the pieces the simplified static site no longer needed.

**Why:** Leaving unused infrastructure running costs real money for no benefit. Because everything was defined in Terraform, removing exactly the right pieces was a single reviewed command rather than a manual hunt through the AWS Console.

**When:** Once the decision in Stage 6 was made and the static site was ready to replace the old one.

## Stage 8: A Full Reset — Tearing Down Everything, Rebuilding Clean

At one point, the entire environment — including the S3 bucket, CloudFront distribution and Route 53 zone — was deliberately destroyed and rebuilt from scratch, partly to guarantee a clean, cost-free slate and partly to prove the whole setup could be reproduced reliably from code alone.

```
terraform destroy
# ...later...
terraform init
terraform plan
terraform apply
```

Because the Route 53 hosted zone was destroyed and recreated, it received a new set of nameservers — meaning Stage 3 (entering nameservers at the registrar, waiting for propagation) had to be repeated in full.

**When:** Mid-project, as a deliberate reset rather than a reaction to any single failure.

## Stage 9: Fixing an "Already Exists" Error After the Reset

Rebuilding from scratch hit one real error: an S3 bucket name is globally unique, and the bucket from before the reset hadn’t been fully removed.

```
terraform import aws_s3_bucket.frontend rudra-travels-com-frontend
```

**How it works:** import tells Terraform "this resource already exists in AWS — adopt it into your records instead of trying to create a new one." After that, terraform apply continued normally.

**Why:** Terraform only knows what it itself remembers creating. A resource that exists in AWS but isn’t in Terraform’s records causes exactly this kind of conflict — import is the standard fix.

**When:** Immediately after the Stage 8 terraform apply failed on this specific error.

## Stage 10: Deploying the New Static Site

```
../rudra-infra/scripts/deploy-frontend.sh
```

**How it works:** For a plain HTML/CSS/JS site, this script is simple: sync every file in the folder up to S3 (aws s3 sync), then tell CloudFront to clear its cache of the old files (aws cloudfront create-invalidation) so visitors see the update within minutes rather than whenever their cached copy happens to expire.

**When:** This became the routine, repeated command for every content update from this point forward — run from inside the site’s folder, dozens of times, throughout the rest of the project.

## Stage 11: A Real Mistake — Deleting the Terraform State File

While tidying up project folders, an rm -rf command deleted an entire folder to replace it with a fresh copy — which also deleted terraform.tfstate, the file Terraform uses to remember what it has already built.

```
terraform plan
```

This returned "14 to add" — Terraform, having lost its memory, believed none of the real infrastructure existed and was prepared to create a second, duplicate copy of all of it.

**This apply was not run.** Recognising the danger from the plan output before applying anything is the actual point of running plan first — exactly what it’s for.

### The safe workaround for the one specific pending change

```
aws route53 change-resource-record-sets --hosted-zone-id <ID> --change-batch '{ ... }'
```

**Why:** A single additive DNS record, applied directly via the AWS CLI, carries no risk of duplicating anything — unlike running Terraform against a state file that no longer matches reality.

**When:** Partway through Stage 12 below, discovered while trying to add one new DNS record.

**Still outstanding:** properly reconciling Terraform’s state with what actually exists in AWS (a full terraform import pass), and moving state to a remote backend (S3) so a local folder deletion can never cause this again.

## Stage 12: Setting Up Google Search Console

To get the site indexed by Google, ownership of the domain needed verifying, and a sitemap needed submitting.

### Verification

Google provided a TXT record value to add to DNS. Since this project’s DNS lives in Route 53 (not at the registrar), the record was added as Terraform config in principle, but ultimately applied directly due to the Stage 11 state issue:

```
aws route53 change-resource-record-sets --hosted-zone-id <ID> --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"rudra-travels.com","Type":"TXT","TTL":300,"ResourceRecords":[{"Value":"\"google-site-verification=...\""}]}}]}'
```

### Verifying it worked

Checked directly in the Search Console UI (a "Verified" confirmation), no CLI equivalent for this specific check.

### Confirming the sitemap file itself was really live

```
curl -s https://rudra-travels.com/sitemap.xml
```

Then submitted inside Search Console’s own interface (Sitemaps section, entering the path).

**When:** Near the end of the project, once the site’s content was considered stable enough to start actively pursuing search visibility.

## Stage 13: The Ongoing Cycle — What Every Later Update Looked Like

Every content change from this point on followed the same repeating pattern:

- Get the updated files into the local site folder
- Sanity-check before deploying: `grep -c "some-expected-text" script.js` to confirm the right version is actually about to be deployed
- Deploy: `../rudra-infra/scripts/deploy-frontend.sh`
- Verify live: `curl -s https://rudra-travels.com/script.js | grep -c "some-expected-text"`
That second check — confirming the local file is correct before deploying — exists because of a real incident where a deploy ran perfectly but from an outdated local folder, making it look like the deploy itself was broken when it wasn’t.

---

## Quick Reference — Every Command In This Guide, In Order

```
aws --version
terraform --version
aws sts get-caller-identity
ls ~/.ssh/id_ed25519.pub  &&  cat ~/.ssh/id_ed25519.pub
curl ifconfig.me
cat > terraform.tfvars << 'EOF'  ...  EOF
terraform init
terraform plan
terraform apply
aws route53 list-hosted-zones-by-name --dns-name <domain> --query "HostedZones[0].Id" --output text
aws route53 get-hosted-zone --id <ZONE_ID> --query "DelegationSet.NameServers" --output table
dig <domain> NS
npm install
../rudra-infra/scripts/deploy-frontend.sh
ssh ubuntu@<ip>
nano /home/ubuntu/rtt-backend/.env
../rudra-infra/scripts/deploy-backend.sh
sudo certbot --nginx -d <subdomain> --non-interactive --agree-tos -m <email> --redirect
curl -s https://<domain>/ | grep -o '...'
terraform destroy
terraform import <resource> <real-id>
aws route53 change-resource-record-sets --hosted-zone-id <ID> --change-batch '{...}'
curl -s https://<domain>/sitemap.xml
```
