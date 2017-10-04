#!/bin/bash
RELEASE_CHANNEL=$1
PROJECT_ID=$2
_release_source="releases/$RELEASE_CHANNEL/release.json"
_new_version=$(cat $_release_source | jq -r '.resources[] | select(.resource == "operator") | .version')

# move operator tag
_repo="gcr.io/$PROJECT_ID"
_version_tagged_image=$_repo/puppet-discovery-operator:$_new_version

set -x
set -e
docker pull $_version_tagged_image
docker tag $_version_tagged_image $_repo/puppet-discovery-operator:$RELEASE_CHANNEL
docker push $_repo/puppet-discovery-operator:$RELEASE_CHANNEL
set +x

# also tag preview with 'latest'
if [[ "$RELEASE_CHANNEL" == "preview" ]] ; then
  set -x
  docker tag $_version_tagged_image $_repo/puppet-discovery-operator:latest
  docker push $_repo/puppet-discovery-operator:latest
  set +x
fi

echo "------------------------------------"
echo "Successfully tagged $_version_tagged_image for channel $RELEASE_CHANNEL"
