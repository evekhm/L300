gcloud compute  instances create   "$SRC_VM_ID"  --zone=us-east1-d --machine-type=e2-standard-2 \
  --subnet=default --scopes="cloud-platform"   --tags=http-server,https-server \
  --image=ubuntu-minimal-1604-xenial-v20210119a   --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard   --boot-disk-device-name="$SRC_VM" \
  --metadata startup-script='#! /bin/bash
  # Installs apache and a custom homepage
  sudo su -
  apt-get update
  apt-get install -y apache2
  cat <<EOF > /var/www/html/index.html
  <html><body><h1>Hello World</h1>
  <p>This page was created from a simple start up script!</p>
  </body></html>
  EOF'

gcloud compute firewall-rules create default-allow-http --direction=INGRESS \
 --priority=1000 --network=default --action=ALLOW   --rules=tcp:80 \
 --source-ranges=0.0.0.0/0 --target-tags=http-server