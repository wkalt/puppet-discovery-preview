FROM gcr.io/cloud-builders/docker
RUN apt-get update && apt-get install -y jq
ADD build/tag.sh /tag.sh
ADD build/release-helper.sh /release-helper.sh
ENTRYPOINT ["/tag.sh"]
