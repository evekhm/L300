#! /bin/bash
#set -e # Exit if error is detected during pipeline execution

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#1. Create a processing cluster
echo "Creating a processing cluster..."
gcloud container clusters create $CLUSTER  --project=$PROJECT_ID \
  --zone="$ZONE" --machine-type e2-standard-4   --image-type ubuntu_containerd \
  --num-nodes "$NUM_NODES" --enable-stackdriver-kubernetes   \
  --subnetwork "projects/$PROJECT_ID/regions/$REGION/subnetworks/default"

#2. Install Migrate to Containers
echo "Creating service account for the migration..."
#service account for the migration and initialize Migrate to Containers
gcloud iam service-accounts create $SA_INSTALL \
  --project=$PROJECT_ID

#Grant the storage.admin role to the service account:
gcloud projects add-iam-policy-binding $PROJECT_ID  \
  --member="serviceAccount:$SA_INSTALL@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

#Download the key file for the service account:
gcloud iam service-accounts keys create "$SA_INSTALL".json \
  --iam-account="$SA_INSTALL"@$PROJECT_ID.iam.gserviceaccount.com \
  --project=$PROJECT_ID

#connect to cluster
gcloud container clusters get-credentials $CLUSTER --zone $ZONE

#Set up Migrate to Containers
echo "Installing Migrate to Containers..."
migctl setup install --json-key="$SA_INSTALL".json --gcp-project $PROJECT_ID --gcp-region $REGION

#Validate the Migrate to Containers installation
echo "Validating Migration..."
migctl doctor

#3 Migrating the VM

#Create a service account for Compute Engine source migrations
echo "Creating a service account for Compute Engine source migrations..."
gcloud iam service-accounts create "$SA_MIGRATE" \
  --project=$PROJECT_ID

#Grant the compute.viewer role to the service account:
gcloud projects add-iam-policy-binding "$PROJECT_ID"  \
  --member="serviceAccount:$SA_MIGRATE@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.viewer"

#Grant the compute.storageAdmin role to the service account:
gcloud projects add-iam-policy-binding "$PROJECT_ID"  \
  --member="serviceAccount:$SA_MIGRATE@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.storageAdmin"

#Download the key file for the service account
gcloud iam service-accounts keys create "$SA_MIGRATE".json \
  --iam-account="${SA_MIGRATE}"@"$PROJECT_ID".iam.gserviceaccount.com \
  --project="$PROJECT_ID"

#Create the migration source:
echo "Creating the migration source..."
migctl source create ce "$SRC_VM" --project "$PROJECT_ID" --json-key="$SA_MIGRATE".json

#Create a migration
echo "Creating the migration job..."
migctl migration create "$MIGRATION_JOB" --source source-vm   --vm-id "$SRC_VM" --type linux-system-container

#check the status
echo "Chechking the status of the migration job..."
migctl migration status "$MIGRATION_JOB"

#Review the migration plan
migctl migration get "$MIGRATION_JOB"

echo "Below is the K8s CRD for migration object"
cat "$MIGRATION_JOB".yaml

echo "To update the plan run: migctl migration update $MIGRATION_JOB"






