FROM gcr.io/cloud-builders/gcloud
RUN apt-get update && apt-get install -y jq curl
ADD build/push.sh /push.sh
ENTRYPOINT ["/push.sh"]
