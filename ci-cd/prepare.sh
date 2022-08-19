#! /bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#set -e # Exit if error is detected during pipeline execution
export PROJECT_ID=$(gcloud config get-value project)
export WORKLOAD_POOL=${PROJECT_ID}.svc.id.goog

source "$DIR"/SET

enable_project_apis() {
  APIS="compute.googleapis.com \
    sourcerepo.googleapis.com \
    cloudbuild.googleapis.com"

  echo "Enabling APIs on the project..."
  gcloud services enable $APIS --async
}

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
   --enable-stackdriver-kubernetes \
   --network default \
   --subnetwork default \
   --workload-pool=${WORKLOAD_POOL}
}

function create_sa(){
  gcloud iam service-accounts create "${CONNECT_SA}"
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${CONNECT_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/gkehub.connect"

  gcloud iam service-accounts keys create "${CONNECT_SA}"-key.json \
  --iam-account="${CONNECT_SA}"@"${PROJECT_ID}".iam.gserviceaccount.com
}

enable_project_apis

# Deploy two clusters, cymbal-bank-prod and cymbal-bank-dev, both in the us-central1-a zone.
create_cluster "$CLUSTER_DEV"
create_cluster "$CLUSTER_PROD"
