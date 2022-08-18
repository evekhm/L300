gcloud compute  instances create   source-vm  --zone=$ZONE --machine-type=e2-standard-2  \
 --subnet=default --scopes="cloud-platform"   --tags=http-server,https-server \
 --image=ubuntu-minimal-1604-xenial-v20210119a   --image-project=ubuntu-os-cloud \
 --boot-disk-size=10GB --boot-disk-type=pd-standard   --boot-disk-device-name=source-vm \
  --metadata startup-script=METADATA_SCRIPT

gcloud compute firewall-rules create default-allow-http --direction=INGRESS \
 --priority=1000 --network=default --action=ALLOW   --rules=tcp:80 \
 --source-ranges=0.0.0.0/0 --target-tags=http-server