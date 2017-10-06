FROM gcr.io/cloud-builders/docker
RUN apt-get update && apt-get install -y jq
ADD build/promote-public.sh /promote-public.sh
ENTRYPOINT ["/promote-public.sh"]
