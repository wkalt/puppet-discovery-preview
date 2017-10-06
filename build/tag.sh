#!/bin/bash
RELEASE_CHANNEL=$1
PROJECT_ID=$2

source /release-helper.sh "$@"

if [[ "$RELEASE_CHANNEL" == "demo" ]]; then
    _project_id="puppet-dig"
else
    _project_id=$PROJECT_ID
fi

# move operator tag
_repo="gcr.io/$_project_id"
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
