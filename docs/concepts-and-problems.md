# From Zero to Live: A Complete Guide to Deploying a Static Website on AWS with Terraform

**What this document is:** a full, honest walkthrough of every real cloud
engineering decision, problem, and fix involved in taking a website from
nothing to a live, production, DNS-resolving, SSL-secured site on AWS —
written so that someone with no prior AWS experience could follow the same
path and understand not just *what* was done, but *why*, and what actually
went wrong along the way.

This isn't a polished highlight reel. It includes the mistakes.

---

## Part 1: The Big Picture

### What we were building

A static website (plain HTML/CSS/JS — no server-side code) needed to be:
- Hosted somewhere reliable
- Served fast to visitors anywhere in the world
- Reachable at a real domain name (not some AWS-generated URL)
- Secured with HTTPS
- All of it defined as **code**, not clicked together by hand in a console —
  so it could be torn down, rebuilt, and reasoned about like software

### The architecture, and why each piece exists

```
                         ┌─────────────────────┐
   Visitor's browser ──▶ │   Route 53 (DNS)     │   "what IP address does
                         └──────────┬───────────┘    rudra-travels.com point to?"
                                    │
                         ┌──────────▼───────────┐
                         │   CloudFront (CDN)    │◀── ACM (TLS certificate)
                         └──────────┬───────────┘   "is this connection secure?"
                                    │
                         ┌──────────▼───────────┐
                         │   S3 (static hosting) │   "where are the actual files?"
                         │   HTML / CSS / JS      │
                         │   images               │
                         └───────────────────────┘
```

**Why not just put the files somewhere and call it done?** Because each of
these four services solves a specific problem:

- **S3 (Simple Storage Service)** is just file storage — think of it as a
  folder that lives on Amazon's servers instead of your laptop. On its own,
  S3 can technically serve a website, but it's slow for visitors far from
  wherever the bucket physically lives, and by default nobody but you can
  see the files.
- **CloudFront** is a CDN (Content Delivery Network). It copies your files
  to servers physically distributed around the world, so a visitor in
  Tokyo and a visitor in London both get the site loaded from a nearby
  location instead of one single place. It also gives us a place to attach
  HTTPS.
- **ACM (AWS Certificate Manager)** issues the free TLS certificate that
  makes the padlock appear in a visitor's browser — without it, browsers
  warn visitors the site is "not secure."
- **Route 53** is AWS's DNS service. DNS is the system that translates a
  human-readable name (`rudra-travels.com`) into the actual technical
  address of where CloudFront lives. Without it, nobody could type the
  domain name and reach anything.

### Why Terraform, instead of just clicking around in the AWS Console

Everything above *could* be created by hand, clicking through AWS's web
interface. We didn't do that. Instead, every single resource — the S3
bucket, its permissions, the CloudFront distribution, every DNS record,
the certificate and its validation — is defined in text files using
**Terraform**, a tool for **Infrastructure as Code (IaC)**.

The practical difference this made, demonstrated for real partway through
this project: at one point the whole environment was deliberately torn
down (to eliminate cost while the site's design was being simplified) and
then rebuilt from scratch. Because it was all defined in code, this took
one command (`terraform apply`) and about ten minutes. If it had all been
clicked together by hand, rebuilding it correctly — bucket policies,
DNS records, certificate validation, all of it — would have taken a
frantic afternoon and been very easy to get subtly wrong.

---

## Part 2: Core Concepts, Explained From Scratch

If any of these words are unfamiliar, this section is for you.

**Terraform files (`.tf`)** are plain text files describing what
infrastructure should exist. You write *what you want*, not *the steps to
get there* — Terraform figures out the steps.

**`terraform init`** downloads the "provider" (in our case, the AWS
provider) — the plugin that lets Terraform actually talk to AWS's API.
Run this once per project, and again if the configuration changes
significantly.

**`terraform plan`** is a dry run. It compares what your `.tf` files say
should exist against what Terraform believes currently exists, and prints
a list of what it would create, change, or destroy — without actually
doing anything yet. **Always read this before applying.**

**`terraform apply`** actually makes the real changes in your AWS account.

**`terraform destroy`** tears down everything Terraform is managing.

**Terraform state (`terraform.tfstate`)** is the most important concept
in this whole guide, and the one that caused a real, serious problem
partway through this project (see Part 4). Terraform doesn't magically
know what it built — it keeps a record, a single file called
`terraform.tfstate`, that maps your `.tf` code to the real-world AWS
resource IDs it created. **If this file is lost, Terraform loses all
memory of what it built** — even though the real resources are still
sitting there in AWS, costing money and doing their job. By default, this
file lives locally in your project folder, which — as we found out — makes
it dangerously easy to delete by accident.

---

## Part 3: Building It, Step by Step

### 3.1 — One-time setup

```bash
aws --version              # confirm the AWS CLI is installed
terraform --version        # confirm Terraform is installed
aws sts get-caller-identity  # confirm the CLI is actually connected to a real AWS account
```

### 3.2 — Defining variables

Rather than hardcoding sensitive or environment-specific values directly
into the `.tf` files, they're defined as **variables**, with real values
supplied in a separate `terraform.tfvars` file (which is never committed
anywhere public, since it can contain sensitive detail):

```bash
cat > terraform.tfvars << 'EOF'
domain_name       = "rudra-travels.com"
aws_region        = "eu-west-2"
ssh_public_key    = "ssh-ed25519 AAAA... your-key-here"
allowed_ssh_cidr  = "your.ip.here/32"
EOF
```

### 3.3 — The actual provisioning

```bash
terraform init
terraform plan     # read this output carefully
terraform apply    # type yes when prompted
```

This one command created — in order, because Terraform works out
dependencies automatically — the S3 bucket, its access policies, the ACM
certificate, the DNS records ACM needs to *prove you own the domain*
before it'll issue a certificate, the CloudFront distribution, and the
Route 53 hosted zone with its own records.

### 3.4 — Pointing the real domain at it

Buying a domain (at a registrar like names.co.uk) and having AWS actually
control its DNS are two different things. After `apply`, Terraform's
output includes four **nameservers** — these get entered at the domain
registrar, telling the wider internet "for anything about this domain,
go ask AWS, not us."

```bash
aws route53 get-hosted-zone --id <ZONE_ID> --query "DelegationSet.NameServers" --output table
```

Those four values get pasted into the registrar's "Change Nameservers"
page. This is the step that takes real, unavoidable waiting — DNS changes
propagate across the internet's many caching layers gradually, sometimes
in minutes, sometimes (rarely) up to 48 hours.

### 3.5 — Deploying the actual website content

Terraform builds the *infrastructure* — the empty containers. Getting your
actual HTML/CSS/JS files into the S3 bucket is a separate, much simpler,
much more frequent step:

```bash
aws s3 sync . "s3://$BUCKET_NAME" --delete
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*"
```

The second command matters more than it looks. CloudFront caches
(temporarily stores) copies of your files at all its worldwide locations
for speed. If you only update S3 and skip this step, visitors keep seeing
the *old* cached version for hours, because nothing told CloudFront
anything changed. "Invalidation" clears that cache.

---

## Part 4: Everything That Actually Went Wrong, and Why

This is the part most tutorials skip. Real infrastructure work involves
real problems — here is every one encountered on this project, in enough
detail to actually learn from.

### Problem 1: DNS propagation delays and a scary-looking (but harmless) error

**What happened:** right after switching nameservers, running
`dig rudra-travels.com NS` returned a `SERVFAIL` error mentioning
`REFUSED`.

**Why:** this is completely normal mid-propagation. Different DNS
resolvers around the internet update at different speeds; some had
already picked up the change, others hadn't yet. The error even
contained an AWS nameserver IP address in it — proof it was *already
partially working*, just not universally yet.

**Fix:** wait, and re-check periodically with `dig`. No action was
actually needed — the appearance of an error didn't mean anything was
broken.

**Lesson:** distinguish between an error that means "something is
misconfigured" and one that means "a distributed system hasn't finished
converging yet." DNS is the second kind, almost always.

### Problem 2: `S3 BucketAlreadyOwnedByYou`

**What happened:** after tearing down and rebuilding the infrastructure,
`terraform apply` failed with an error saying the S3 bucket already
existed.

**Why:** S3 bucket names are globally unique, and buckets that still
contain files sometimes survive a `terraform destroy` if the destroy
didn't fully complete or the bucket wasn't properly emptied first.
Terraform, working from a fresh state, had no memory of that bucket and
tried to create a new one with the same name — which AWS correctly
refused, since it already existed.

**Fix:**
```bash
terraform import aws_s3_bucket.frontend rudra-travels-com-frontend
```
`import` tells Terraform "this resource already exists in AWS — adopt it
into your state file instead of creating a new one." After that,
`terraform apply` continued normally.

**Lesson:** Terraform's state and AWS's actual reality can drift apart.
`import` is the tool for reconciling them.

### Problem 3: The Terraform state file got deleted — the most serious issue in this whole project

**What happened:** while reorganizing project folders, a
`rm -rf` command deleted the entire `rudra-infra` folder to replace it
with a fresh copy. This included `terraform.tfstate`. The next
`terraform plan` showed **14 resources to add** — Terraform believed
*nothing existed yet*, and was one `apply` away from creating an entire
second, duplicate set of infrastructure (a second S3 bucket, a second
CloudFront distribution, a second DNS zone) sitting alongside the real,
live one.

**Why this is dangerous:** the real resources were completely fine and
still serving the live site the whole time — the problem was purely that
Terraform's *memory* of them was gone. Had `apply` been run anyway, the
result would have been duplicate infrastructure, real extra AWS cost, and
likely DNS conflicts between two competing hosted zones for the same
domain.

**The immediate fix:** the one specific pending change (a new DNS TXT
record for Google verification) was applied directly through the AWS
CLI instead of through Terraform, since a single additive DNS record
carries no risk of duplication:
```bash
aws route53 change-resource-record-sets --hosted-zone-id <ID> --change-batch '{ ... }'
```

**The real, underlying fix (recommended, not yet done as of writing):**
move Terraform's state to **remote storage** — typically an S3 bucket
created specifically for this purpose, configured as a `backend` in
Terraform. This is often called a "Terraform bootstrap" setup. With
remote state, the state file can never be lost to a local folder
deletion, and it also enables safe collaboration if more than one person
ever runs Terraform against the same infrastructure.

**Lesson:** local Terraform state is a real, sharp edge. It works fine
until the one day a folder gets deleted or a laptop dies. Remote state
turns a catastrophic, hard-to-diagnose problem into a non-event.

### Problem 4: Multiple confusable copies of the same project folder

**What happened:** across many rounds of downloading updated zip files,
several folders named things like `rudra-infra`, `rudra-infra-2`,
`files-11/rudra-infra` ended up scattered across the Downloads folder —
some stale, only one actually correct (the one Terraform's state,
before it was lost, actually corresponded to).

**Why this matters:** running a Terraform command from the *wrong* copy
of the folder is exactly what nearly caused the Problem 3 disaster —
`../rudra-infra` resolved to an empty, unrelated folder at one point,
producing a bucket-name error that looked like a bug but was actually a
path problem.

**Lesson:** in real infrastructure work, *which exact folder you're
standing in* when you run a command is not a minor detail — it can be the
difference between a safe operation and a dangerous one. Verifying with a
quick `grep` or `ls` before running anything destructive is cheap
insurance.

### Problem 5: Google Search Console wanted DNS verification, but where?

**What happened:** Google's verification instructions said "sign in to
your domain name provider" — but the domain's *registrar* (names.co.uk)
no longer controlled its DNS at all; Route 53 did, ever since the
nameserver switch in Part 3.4.

**Fix:** the TXT record Google needed was added as a Terraform resource
(`aws_route53_record`, type `TXT`) in the same `route53.tf` file as
everything else — keeping it consistent with the rest of the
infrastructure-as-code approach, rather than a one-off manual change.
(Though, per Problem 3, it ultimately had to be applied via direct AWS
CLI that one time due to the state issue.)

**Lesson:** always check *which system actually controls DNS right now*
before following generic setup instructions — "your domain provider" is
ambiguous the moment a registrar and a DNS host are different services.

### Problem 6: "The site hasn't changed" — stale local files, not a broken deploy

**What happened:** after deploying what should have been updated code,
the live site appeared completely unchanged.

**Diagnosis process:**
```bash
curl -s https://rudra-travels.com/script.js | grep -c "some-recent-change"
```
This returned `0` — but so did checking the *local* file about to be
deployed:
```bash
grep -c "some-recent-change" ./script.js
```
That confirmed the real cause: the local folder being deployed was itself
an outdated copy, not the deploy process failing. The deploy script had
worked perfectly every time — it had just been faithfully uploading old
content.

**Lesson:** when something "isn't updating," check the *source* being
deployed before assuming the *deploy mechanism* is broken. `curl`-ing the
live site directly (bypassing any browser cache) is a fast way to see
what's actually being served, separate from what's on screen.

### Problem 7: Trusting unverified content from elsewhere

**What happened:** a batch of code from a separate work session included
over 70 image URLs pointing at a stock photo site. Several were
fabricated — plausible-looking but non-existent — causing broken images
across the live site.

**How it was caught:** a pattern in the URLs themselves was the tell —
several were nearly identical, differing by only a couple of digits,
which is not how real, independently-published photo IDs actually look.
Spot-checking one directly confirmed it was broken.

**Fix:** rather than trying to individually verify dozens of URLs (slow,
and each one only as trustworthy as the last), every one was replaced
with content that could be verified as actually loading — either real
local images, or freshly re-sourced and directly checked before use.

**Lesson (general software engineering, not cloud-specific, but just as
important):** never assume content — including code, links, or data —
handed to you from another source is correct just because it looks
plausible. Verify by actually testing it, especially anything that came
from an automated or unfamiliar process.

---

## Part 5: What This Project Actually Demonstrates

- Real Infrastructure as Code, not just clicking around a console
- Understanding of DNS, TLS/SSL certificates, and CDN caching — not just
  "it works," but *why* each piece is there
- Debugging real, live infrastructure problems using the actual tools
  (`dig`, `curl`, `terraform plan`, AWS CLI) rather than guessing
- Recognizing and recovering from a serious operational mistake (lost
  Terraform state) without making it worse
- Knowing the difference between a code problem and a stale-data problem
- A clear-eyed understanding of what's still unfinished (remote state)
  and why it matters — not overstating the work as more polished than it is

## Part 6: What's Still Left To Do, If You're Following This as a Guide

- **Set up remote Terraform state** (S3 backend) so local folder mistakes
  can never again disconnect Terraform from reality
- **Reconcile Terraform's state with AWS's actual current resources**
  properly (a full `terraform import` pass), rather than relying on the
  one-off AWS CLI workaround
- Consider a CI/CD pipeline (e.g., GitHub Actions) to run `terraform plan`
  automatically on every change, rather than running it by hand
