#!/bin/bash
RELEASE_CHANNEL=$1
PROJECT_ID=$2
SOURCE_ID=$3

_release_source="releases/$RELEASE_CHANNEL/release.json"
_new_version=$(cat $_release_source | jq -r '.resources[] | select(.resource == "operator") | .version')

# pull release from puppet-dig
_source_repo="gcr.io/$SOURCE_ID"

set -x
set -e
docker pull $_source_repo/cloud-discovery-controller:$_new_version
docker pull $_source_repo/cloud-discovery-agent:$_new_version
docker pull $_source_repo/update-checker:$_new_version
docker pull $_source_repo/sysctl-helper:$_new_version
docker pull $_source_repo/puppet-discovery-operator:$_new_version
docker pull $_source_repo/pdp-ingest:$_new_version
docker pull $_source_repo/pdp-query:$_new_version
docker pull $_source_repo/static-ui:$_new_version

# move release tag to public
_destination_repo="gcr.io/$PROJECT_ID"

docker tag $_source_repo/cloud-discovery-controller:$_new_version $_destination_repo/cloud-discovery-controller:$_new_version
docker tag $_source_repo/cloud-discovery-agent:$_new_version $_destination_repo/cloud-discovery-agent:$_new_version
docker tag $_source_repo/update-checker:$_new_version $_destination_repo/update-checker:$_new_version
docker tag $_source_repo/sysctl-helper:$_new_version $_destination_repo/sysctl-helper:$_new_version
docker tag $_source_repo/puppet-discovery-operator:$_new_version $_destination_repo/puppet-discovery-operator:$_new_version
docker tag $_source_repo/pdp-ingest:$_new_version $_destination_repo/pdp-ingest:$_new_version
docker tag $_source_repo/pdp-query:$_new_version $_destination_repo/pdp-query:$_new_version
docker tag $_source_repo/static-ui:$_new_version $_destination_repo/static-ui:$_new_version

# push release to public

docker push $_destination_repo/cloud-discovery-controller:$_new_version
docker push $_destination_repo/cloud-discovery-agent:$_new_version
docker push $_destination_repo/update-checker:$_new_version
docker push $_destination_repo/sysctl-helper:$_new_version
docker push $_destination_repo/puppet-discovery-operator:$_new_version
docker push $_destination_repo/pdp-ingest:$_new_version
docker push $_destination_repo/pdp-query:$_new_version
docker push $_destination_repo/static-ui:$_new_version
set +x

echo "------------------------------------"
echo "Successfully moved version $_new_version to public repo"
