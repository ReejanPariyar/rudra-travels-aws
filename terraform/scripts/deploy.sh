#!/bin/bash
# Deploys the website in the CURRENT folder to AWS.
#
#   cd my-website
#   bash ../terraform/scripts/deploy.sh yourdomain.com
#
# Unlike the old script, this does NOT depend on Terraform's saved state.
# It asks AWS directly which bucket and CloudFront distribution serve the domain.
# It also shows you what would be deleted from the live site before doing anything.

set -e
DOMAIN="${1:?Usage: bash deploy.sh yourdomain.com   (run from inside your website folder)}"

[ -f index.html ] || { echo "Run this from inside the site folder (index.html not found here)."; exit 1; }

echo "Looking up the live site on AWS..."
read -r DIST_ID ORIGIN <<< "$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$DOMAIN')].[Id,Origins.Items[0].DomainName]" \
  --output text)"

if [ -z "$DIST_ID" ] || [ -z "$ORIGIN" ]; then
  echo "Couldn't find a CloudFront distribution for $DOMAIN. Nothing was changed."
  exit 1
fi

BUCKET="${ORIGIN%%.s3.*}"
BUCKET="${BUCKET%%.s3-*}"
echo "  CloudFront distribution: $DIST_ID"
echo "  S3 bucket:               $BUCKET"
echo

echo "Previewing changes (nothing is uploaded yet)..."
PREVIEW=$(aws s3 sync . "s3://$BUCKET" --delete --exclude "*.md" --exclude ".git/*" --dryrun)
UPLOADS=$(echo "$PREVIEW" | grep -c "(dryrun) upload" || true)
DELETES=$(echo "$PREVIEW" | grep "(dryrun) delete" || true)
DELETE_COUNT=$(echo "$DELETES" | grep -c . || true)
echo "  $UPLOADS file(s) to upload or update"
echo "  $DELETE_COUNT file(s) to remove from the live site"
if [ "$DELETE_COUNT" -gt 0 ]; then
  echo
  echo "Files that will be REMOVED from the live site:"
  echo "$DELETES" | sed 's/^/    /'
fi
echo

read -r -p "Go ahead and deploy? (y/N) " ANSWER
ANSWER=$(echo "$ANSWER" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "$ANSWER" in
  y|yes) ;;
  *) echo "Cancelled. Nothing was changed."; exit 0 ;;
esac

echo
echo "Uploading..."
aws s3 sync . "s3://$BUCKET" --delete --exclude "*.md" --exclude ".git/*"

echo "Telling browsers to re-check the page, script and style files on every visit..."
# (Images keep their normal caching so the site stays fast.)
aws s3 cp . "s3://$BUCKET/" --recursive --exclude "*" \
  --include "*.html" --include "*.js" --include "*.css" \
  --cache-control "no-cache" > /dev/null

echo "Clearing CloudFront's cache..."
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" > /dev/null

echo
echo "Done. The new version will be live at https://$DOMAIN in a couple of minutes."
