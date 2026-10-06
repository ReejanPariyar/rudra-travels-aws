#!/bin/bash
# Run this from inside your website's own folder (the one with index.html
# in it), pointing at wherever you put this terraform/ folder relative to
# it. Adjust TF_DIR below if your layout differs.
#
# Example layout:
#   my-project/
#     my-website/          <- run this script from here
#     terraform/                   <- this terraform folder, as a sibling
set -e

TF_DIR="../terraform"

BUCKET=$(cd "$TF_DIR" && terraform output -raw frontend_bucket_name)
DISTRIBUTION_DOMAIN=$(cd "$TF_DIR" && terraform output -raw cloudfront_domain)

echo "Uploading to s3://$BUCKET ..."
aws s3 sync . "s3://$BUCKET" --delete --exclude "*.md" --exclude ".git/*"

echo "Finding CloudFront distribution ID to invalidate its cache..."
DIST_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$DISTRIBUTION_DOMAIN'].Id" --output text)
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*"

echo "Done. Changes will be live in a couple of minutes."
