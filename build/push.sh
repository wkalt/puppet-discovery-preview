#!/bin/bash
RELEASE_CHANNEL=$1
_release_source="releases/$RELEASE_CHANNEL/release.json"
_target_bucket='uhvwcgv0ierpc2nvdmvyesbqcmv2awv3cg'
_new_version=$(cat $_release_source | jq -r '.resources[] | select(.resource == "operator") | .version')
_old_version=$(curl http://storage.googleapis.com/$_target_bucket/$_release_source | jq -r '.resources[] | select(.resource == "operator") | .version')

if [[ -z "$_new_version" ]] || [[ -z "$_old_version" ]] ; then
  echo "Failed to check version(s) for $RELEASE_CHANNEL."
  exit 1
fi

if [[ "$_new_version" == "$_old_version" ]] ; then
  echo "$RELEASE_CHANNEL is already on version $_new_version, nothing to do."
  exit 0
fi

# push release file to gs
_target_file=gs://$_target_bucket/$_release_source
set -x
gsutil cp $_release_source $_target_file
gsutil setmeta -h 'Content-Type:application/json' -h 'Cache-Control:no-cache, max-age=0, no-transform' $_target_file
gsutil acl ch -u AllUsers:R $_target_file
set +x

echo "------------------------------------"
echo "Successfully pushed $_release_source"
