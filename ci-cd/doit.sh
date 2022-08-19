#!/bin/bash

COLOR_RED=$(tput setaf 1)
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_BLUE=$(tput setaf 4)
COLOR_MAGENTA=$(tput setaf 5)
COLOR_CYAN=$(tput setaf 6)
COLOR_WHITE=$(tput setaf 7)
RESET=$(tput sgr0)

check_task(){
  local TASK=$1
  read -p "${COLOR_BLUE}check the progress on $TASK and hit ENTER when it is ${RESET} ${COLOR_GREEN}green ${RESET}"
}

print(){
  echo "${COLOR_CYAN}$1${RESET}"
}

printh(){
  echo "${COLOR_YELLOW}$1${RESET}"
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S="$DIR"/bank-of-anthos
source "$DIR"/SET

function enable_project_apis() {
  APIS="compute.googleapis.com \
    sourcerepo.googleapis.com \
    container.googleapis.com \
    gkehub.googleapis.com \
    cloudbuild.googleapis.com"
  echo "Enabling APIs on the project..."
  gcloud services enable $APIS
  sleep 5

  if [[ $ARGOLIS == 'true' ]]; then
    echo "Disabling constraints for Argolis ..."
    gcloud services enable orgpolicy.googleapis.com
    sleep 15
    gcloud org-policies reset constraints/compute.vmExternalIpAccess --project $PROJECT_ID
    gcloud org-policies reset  constraints/compute.requireShieldedVm --project $PROJECT_ID
    gcloud org-policies reset  constraints/compute.requireOsLogin --project $PROJECT_ID
    gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project $PROJECT_ID
  fi
}

function setup_network(){
  local NETWORK=default
  network=$(gcloud compute networks list --filter="name=(\"$NETWORK\" )" --format='get(NAME)' 2>/dev/null)
  if [ -z "$network" ]; then
      gcloud compute networks create $NETWORK --project="$PROJECT_ID" --subnet-mode=auto
  fi
}

function create_cluster() {
  NAME=$1
  echo "Creating $NAME cluster"
  gcloud container clusters create $NAME \
   --project ${PROJECT_ID} \
   --zone=$ZONE \
   --enable-ip-alias \
   --num-nodes 2 \
   --machine-type "n1-standard-4"  \
   --image-type "UBUNTU" \
   --network default \
   --subnetwork default \
   --workload-pool=${WORKLOAD_POOL}
}

function t9_create_cloud_src_repo(){
  local TASK="Task 9"
  print "$TASK: Create a Cloud Source Repository for Cymbal Bank"

  echo "Creating a Google Cloud source repository called $REPO..."
  #Create a Google Cloud source repository called cymbal-bank-repo.
  # Clone the Bank of Anthos original repo from https://github.com/GoogleCloudPlatform/bank-of-anthos.git,
  # and then add your repository as a remote and push your local repository into that remote
  gcloud source repos create $REPO

  if [ -d bank-of-anthos ]; then
    rm -rf bank-of-anthos
  fi
  git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git
  cd bank-of-anthos || exit
  git reset --hard 802d39e17c6bc7ddfe87dde82b94af9aca0e7397
  git config credential.helper gcloud.sh
  git remote add google https://source.developers.google.com/p/${PROJECT_ID}/r/"$REPO"
  git config --global user.email "user1@qwiklabs.net"
  git config --global user.name "user1"
  git add .
  git commit -m "pushing code"
  git push --all google
  check_task "$TASK"
#  read -p "check the progress on $TASK and hit ENTER when it is green"
}

function t10_deploy_gke_prod(){
  local TASK="Task 10"
  print "$TASK: Deploy a Kubernetes Engine Cluster for Cymbal Bank production code"
  #Deploy a two node Kubernetes Engine Cluster called cymbal-bank-prod in us-central1-a.
  create_cluster "$CLUSTER_PROD"

  gcloud container clusters get-credentials $CLUSTER_PROD --zone $ZONE --project ${PROJECT_ID}
  kubectl apply -f "$K8S"/extras/jwt/jwt-secret.yaml --context=${CTX_1}

  #modify the /kubernetes-manifests/frontend.yaml manifest file to include the labels identifying this as version 1
  rm "$K8S"/kubernetes-manifests/frontend.yaml
cat << EOF > "$K8S"/kubernetes-manifests/frontend.yaml
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    version: v1
spec:
  selector:
    matchLabels:
      app: frontend
      version: v1
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      serviceAccountName: default
      terminationGracePeriodSeconds: 5
      containers:
      - name: front
        image: gcr.io/bank-of-anthos/frontend:v0.4.2
        volumeMounts:
        - name: publickey
          mountPath: "/root/.ssh"
          readOnly: true
        env:
        - name: VERSION
          value: "v0.4.2"
        - name: PORT
          value: "8080"
        - name: ENABLE_TRACING
          value: "true"
        - name: SCHEME
          value: "http"
         # Valid levels are debug, info, warning, error, critical. If no valid level is set, gunicorn will default to info.
        - name: LOG_LEVEL
          value: "info"
        # Set to "true" to enable the CymbalBank logo + title
        # - name: CYMBAL_LOGO
        #   value: "false"
        # Customize the bank name used in the header. Defaults to 'Bank of Anthos' - when CYMBAL_LOGO is true, uses 'CymbalBank'
        # - name: BANK_NAME
        #   value: ""
        - name: DEFAULT_USERNAME
          valueFrom:
            configMapKeyRef:
              name: demo-data-config
              key: DEMO_LOGIN_USERNAME
        - name: DEFAULT_PASSWORD
          valueFrom:
            configMapKeyRef:
              name: demo-data-config
              key: DEMO_LOGIN_PASSWORD
        envFrom:
        - configMapRef:
            name: environment-config
        - configMapRef:
            name: service-api-config
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 10
        livenessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 30
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 256Mi
      volumes:
      - name: publickey
        secret:
          secretName: jwt-key
          items:
          - key: jwtRS256.key.pub
            path: publickey
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 8080
EOF

  echo "Deploying manifests ..."
  kubectl apply -f "$K8S"/kubernetes-manifests --context=${CTX_1}
  check_task "$TASK"
  #read -p "${COLOR_BLUE}check the progress on $TASK and hit ENTER when it is green${RESET}"
}

function t11_create_cloud_build_trigger_deploy_to_prod(){
  local TASK="Task 11"
  print "$TASK: Create a Cloud Build template and trigger for deployment to the production cluster"

  function cloud_build_sa(){
    #You must ensure that the Cloud Build Service Account has been bound to the roles/container.admin role in your project.
    PROJECT_NUM=$(gcloud projects describe "$PROJECT_ID" --format='get(projectNumber)')
    CB_ACCOUNT=${PROJECT_NUM}@cloudbuild.gserviceaccount.com
    echo "Bounding Cloud Build Service Account to the roles/container.admin role "
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${CB_ACCOUNT}" \
    --role="roles/container.admin"

    gcloud projects get-iam-policy ${PROJECT_ID}  --flatten="bindings[].members" \
     --format='table(bindings.role)' --filter="bindings.members:${CB_ACCOUNT}"
  }

  #Cloud Build
  #Cloud Build YAML template file that deploys all of the Kubernetes manifests
  # to the cymbal-bank-prod Kubernetes Engine Cluster using a Cloud Build
  # gcr.io/cloud-builders/kubectl step, and then use the same component to
  # delete all pods to force the redeployment to reinitialize all of the component services.
  cloud_build_sa

cat << EOF > "$DIR"/cloudbuild.yaml
steps:
- name: 'gcr.io/cloud-builders/kubectl'
  args: [ apply, -f, ./kubernetes-manifests ]
  env:
  - 'CLOUDSDK_COMPUTE_ZONE=us-central1-a'
  - 'CLOUDSDK_CONTAINER_CLUSTER=cymbal-bank-prod'
- name: 'gcr.io/cloud-builders/kubectl'
  args: [ rollout, restart, deployment, -n, default ]
  env:
  - 'CLOUDSDK_COMPUTE_ZONE=us-central1-a'
  - 'CLOUDSDK_CONTAINER_CLUSTER=cymbal-bank-prod'
EOF

  echo "Pushing cloudbuild.yaml..."
  cat "$DIR"/cloudbuild.yaml
  # create a global (non-regional) Cloud Build Trigger that is fired whenever
  # there's a push to the main branch for your repository.
  gcloud beta builds triggers create cloud-source-repositories --repo="$REPO" --branch-pattern=master  --build-config="$DIR"/cloudbuild.yaml
  git add .
  git commit -m "pushing cloudbuild.yaml"

  echo "Triggering the production pipeline by making a git commit and git push to the main branch..."
  git push --all google  #Push all branches

  #read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t12_deploy_gke_dev(){
  local TASK="Task 12"
  print "$TASK: Deploy a Kubernetes Engine Cluster for Cymbal Bank development code"
  # Deploy another two node Kubernetes Engine Cluster called cymbal-bank-dev in us-central1-a
  # and manually deploy an initial version of the Bank of Anthos application
  # to ensure it is working correctly.
  create_cluster "$CLUSTER_DEV"
  kubectl apply -f "$K8S"/extras/jwt/jwt-secret.yaml  --context=${CTX_2}
  kubectl apply -f "$K8S"/kubernetes-manifests --context=${CTX_2}
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t13_create_cloud_build_trigger_deploy_to_dev(){
  local TASK="Task 13"
  print "$TASK: Create a Cloud Build template and trigger for deployment to the development cluster"

  #Create a new branch called cymbal-dev. In this branch, modify the
  # Bank of Anthos application to display the new Cymbal Bank logo in the header.
  # This is done by uncommenting the "CYMBAL_LOGO" env variable defined
  # in /kubernetes-manifests/frontend.yaml and changing its value
  # (on the next line) from "false" to "true".
  git checkout -b cymbal-dev

  sed -i 's/# - name: CYMBAL_LOGO/- name: CYMBAL_LOGO/g' "$K8S"/kubernetes-manifests/frontend.yaml
  sed -i 's/#   value: "false"/  value: "true"/g' "$K8S"/kubernetes-manifests/frontend.yaml
  sed -i 's/cymbal-bank-prod/cymbal-bank-dev/g' "$DIR"/cloudbuild.yaml

  # Also, you must also modify the /kubernetes-manifests/frontend.yaml
  # manifest file to include the labels identifying this as version 2
  sed -i 's/version: v1/version: v2/g' "$K8S"/kubernetes-manifests/frontend.yaml
  gcloud beta builds triggers create cloud-source-repositories --repo="$REPO" --branch-pattern=cymbal-dev  --build-config="$DIR"/cloudbuild.yaml
  git add .

  #Trigger the development pipeline by making a git commit
  git commit -m "initial push to cymbal-dev branch."
  git push --all google

  echo "You should now have two versions of the application deployed on separate clusters"
  echo "The original production version of the application, that displays Bank
      of Anthos in the header when you connect to the frontend service IP address on the production cluster."
  echo "The development version, that displays Cymbal Bank in the header when you
      connect to the frontend service IP address on the development cluster."
  #read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"

}

# If you are installing ASM v1.10 using install_asm you will have
# to create a service account and use that account to register the
# production cluster with Container Hub before you install ASM
function create_sa(){
  gcloud iam service-accounts create "${CONNECT_SA}"
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${CONNECT_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/gkehub.connect"

  gcloud iam service-accounts keys create "$DIR"/"${CONNECT_SA}"-key.json \
  --iam-account="${CONNECT_SA}"@"${PROJECT_ID}".iam.gserviceaccount.com
}

function register_prod_w_hub(){
  local CLUSTER=$1
    gcloud container hub memberships register "$CLUSTER" \
      --gke-cluster="$ZONE"/"$CLUSTER"  \
      --service-account-key-file="$DIR"/"${CONNECT_SA}"-key.json
}

function t14_create_sa_register_prod_w_hub(){
  local TASK="Task 14"
  print "$TASK: Create a Service account and register the production cluster with Container Hub"
  create_sa
  register_prod_w_hub "$CLUSTER_PROD"
  #read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t17_register_dev_w_hub(){
  local TASK="Task 17"
  print "$TASK: Register the development cluster with Container Hub"
  register_prod_w_hub "$CLUSTER_PROD"
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function install_asm(){
  curl https://storage.googleapis.com/csm-artifacts/asm/install_asm_1.11 > install_asm
  chmod +x install_asm
}

function install_asm_to_gke(){
  local CLUSTER=$1
  ./install_asm \
    --project_id "${PROJECT_ID}" \
    --cluster_name "${CLUSTER}" \
    --cluster_location "$ZONE" \
    --mode install \
    --enable_all
}

function t15_install_asm_to_prod(){
  local TASK="Task 15"
  print "$TASK: Install Anthos Service Mesh onto the production cluster"
  install_asm
  install_asm_to_gke "${CLUSTER_PROD}"
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t18_install_asm_to_dev(){
  local TASK="Task 18"
  print "$TASK: Install Anthos Service Mesh onto the development cluster and configure namespaces"
  install_asm_to_gke "${CLUSTER_DEV}"
  kubectl label namespace default  istio-injection- istio.io/rev=asm-181-5 --overwrite --context=${CTX_2}
  echo "Ensure that the namespace is correctly labelled for Istio sidecar injection.
    All namespaces that required sidecar injection must have an istio.io/rev label
    that matches the installed Anthos Service Mesh version"
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t16_conf_ns_for_sidecar_prod(){
  local TASK="Task 16"
  echo "$TASK: Configure namespace labels for sidecar injection in the production cluster"
  kubectl label namespace default  istio-injection- istio.io/rev=asm-181-5 --overwrite --context=${CTX_1}
  echo "Ensure that the namespace is correctly labelled for Istio sidecar injection.
    All namespaces that required sidecar injection must have an istio.io/rev label
    that matches the installed Anthos Service Mesh version"

#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t19_firewall_4_istio_traffic(){
  local TASK="Task 19"
  print "$TASK: Ensure that you have a firewall rule that allows Istio traffic between clusters"
  # Create a firewall rule called allow-istio that allows Istio service discovery
  # and control plane traffic between your production and development clusters.
  POD_IP_CIDR_1=`gcloud container clusters describe $CLUSTER_PROD --zone $ZONE \
     --format "value(ipAllocationPolicy.clusterIpv4CidrBlock)"`

  POD_IP_CIDR_2=`gcloud container clusters describe $CLUSTER_DEV --zone $ZONE \
     --format "value(ipAllocationPolicy.clusterIpv4CidrBlock)"`

  gcloud compute --project=${PROJECT_ID} firewall-rules create allow-istio \
    --direction=INGRESS --priority=1000 --network=default --action=ALLOW \
    --rules=all --source-ranges=10.128.0.0/20,${POD_IP_CIDR_1},${POD_IP_CIDR_2}
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t16_conf_ns_for_sidecar_prod(){
  local TASK="Task 16"
  print "$TASK: Configure namespace labels for sidecar injection in the production cluster"
  kubectl label namespace default  istio-injection- istio.io/rev=asm-181-5 --overwrite --context=${CTX_1}
  echo "Ensure that the namespace is correctly labelled for Istio sidecar injection.
    All namespaces that required sidecar injection must have an istio.io/rev label
    that matches the installed Anthos Service Mesh version"

#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t20_create_secrets(){
  local TASK="Task 20"
  print "$TASK: Create and apply remote secrets for both clusters"
  # Create a secret with credentials to allow Istio to access remote Kubernetes apiservers
  # These mutual secrets allow the control plane on the production cluster to
  # perform service discovery and other tasks on the development cluster and vice-versa.
  istioctl x create-remote-secret --context=${CTX_1} --name="$CLUSTER_PROD" | kubectl apply -f - --context=${CTX_2}
  istioctl x create-remote-secret --context=${CTX_2} --name="$CLUSTER_DEV" | kubectl apply -f - --context=${CTX_1}
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t21_restart_all_pods(){
  local TASK="Task 21"
  print "$TASK:  Restart all pods to trigger sidecar injection"
  kubectl delete pods --all -n default --context=${CTX_1}
  kubectl delete pods --all -n default --context=${CTX_2}
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t22_create_deploy_istio_gw_vs_prod(){
  local TASK="Task 22"
  print "$TASK:   Create and deploy an Istio Gateway and Virtual Service on the production cluster"
  # create a dedicated namespace for the Istio Ingress gateway on the production cluster called gateway-namespace
  kubectl apply -f "$K8S"/istio-manifests/frontend-ingress.yaml --context=${CTX_1}

  # deploy an Istio ingress gateway called istio-ingressgateway on the production cluster
  export GATEWAY_URL=$(kubectl get svc istio-ingressgateway --context=${CTX_1} \
    -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' -n istio-system)
  echo Istio Gateway Load Balancer: http://$GATEWAY_URL

cat << EOF > destinationrule.yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: frontend
spec:
  host: frontend
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
EOF
  kubectl apply -f destinationrule.yaml --context=${CTX_1}

  echo "Once the ingress gateway and virtual service have been deployed to the
  production cluster you should be able to connect to the external IP-address
  of the gateway to see traffic being redirected between the production and
  development versions of the application as you refresh the page"
  echo
  echo "Check that the istio ingress has been created and is routing traffic to the applications"
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

function t23_update_istio_rebalance_weights(){
  local TASK="Task 23"
  print "$TASK:  Update the Istio virtual service definition to rebalance
    frontend traffic between production and development"

  # Configure your VirtualService to distribute 75% of traffic to
  # the production cluster (v1 frontend) and 25% of traffic to the development cluster (v2 frontend).
cat << EOF > ingress-virtual-service.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
 name: frontend-ingress
spec:
 hosts:
 - "*"
 gateways:
 - frontend-gateway
 http:
 - route:
   - destination:
       host: frontend
       subset: v1
       port:
         number: 80
     weight: 75
   - destination:
       host: frontend
       subset: v2
       port:
         number: 80
     weight: 25
EOF
  kubectl apply -f ingress-virtual-service.yaml --context=${CTX_1}
#  read -p "check the progress on $TASK and hit ENTER when it is green"
  check_task "$TASK"
}

printh "Part 2: Create CI/CD Pipelines for Production and Development"
enable_project_apis
setup_network
t9_create_cloud_src_repo
t10_deploy_gke_prod
t11_create_cloud_build_trigger_deploy_to_prod
t12_deploy_gke_dev
t13_create_cloud_build_trigger_deploy_to_dev

printh "Part 3: Deploy and Configure Anthos Service Mesh"
t14_create_sa_register_prod_w_hub
t15_install_asm_to_prod
t16_conf_ns_for_sidecar_prod
t17_register_dev_w_hub
t18_install_asm_to_dev
t19_firewall_4_istio_traffic
t20_create_secrets
t21_create_secrets
t22_create_deploy_istio_gw_vs_prod
t23_update_istio_rebalance_weights

echo "Congratulations, all completed!."