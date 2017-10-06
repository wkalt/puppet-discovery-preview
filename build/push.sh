#!/bin/bash
RELEASE_CHANNEL=$1

source /release-helper.sh "$@"

# push release file to gs
_target_file=gs://$_target_bucket/$_release_source
set -x
gsutil cp $_release_source $_target_file
gsutil setmeta -h 'Content-Type:application/json' -h 'Cache-Control:no-cache, max-age=0, no-transform' $_target_file
gsutil acl ch -u AllUsers:R $_target_file
set +x

echo "------------------------------------"
echo "Successfully pushed $_release_source"
