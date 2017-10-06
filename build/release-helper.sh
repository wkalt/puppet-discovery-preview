#!/bin/bash

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
