#! /bin/bash
#set -e # Exit if error is detected during pipeline execution

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export WORKLOAD_POOL=${PROJECT_ID}.svc.id.goog
export CTX_1=gke_${PROJECT_ID}_us-central1-a_cymbal-bank-prod
export CTX_2=gke_${PROJECT_ID}_us-central1-a_cymbal-bank-dev
export CTX_3=gke_${PROJECT_ID}_us-central1-a_m4a-processing
export CTX_4=gke_${PROJECT_ID}_us-central1-a_cymbal-monolith-cluster

# Stop VM
echo "Stopping VM $SRC_VM_ID ..."
gcloud compute instances stop "$SRC_VM_ID" --zone "$ZONE"

#1. Create a processing cluster
echo "Creating a processing cluster..."
gcloud container clusters create "$CLUSTER"  --project="$PROJECT_ID" \
  --zone="$ZONE" --machine-type e2-standard-4   --image-type ubuntu_containerd \
  --num-nodes "$NUM_NODES" --enable-stackdriver-kubernetes   \
  --subnetwork "projects/$PROJECT_ID/regions/$REGION/subnetworks/default"

#2. Install Migrate to Containers
echo "Creating service account for the migration..."
#service account for the migration and initialize Migrate to Containers
gcloud iam service-accounts create "$SA_INSTALL" \
  --project="$PROJECT_ID"

#Grant the storage.admin role to the service account:
gcloud projects add-iam-policy-binding "$PROJECT_ID"  \
  --member="serviceAccount:$SA_INSTALL@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

#Download the key file for the service account:
gcloud iam service-accounts keys create "$SA_INSTALL".json \
  --iam-account="$SA_INSTALL"@"$PROJECT_ID".iam.gserviceaccount.com \
  --project="$PROJECT_ID"

#connect to cluster
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE"

#Set up Migrate to Containers
echo "Installing Migrate to Containers..."
migctl setup install --json-key="$SA_INSTALL".json --gcp-project "$PROJECT_ID" --gcp-region $REGION

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
echo "Creating the Compute Engine as the migration source..."
#service account used to create the Compute Engine source
migctl source create ce "$SRC_NAME" --project "${PROJECT_ID}" --json-key="$SA_MIGRATE".json

#Create a migration plan
echo "Creating the migration plan..."
migctl migration create "$MIGRATION_JOB" --source "$SRC_NAME"   --vm-id "$SRC_VM" --type linux-system-container

echo "check in another terminal on progress by running"
echo " migctl migration status $MIGRATION_JOB"
read -p "Hit ENTER to continue"

echo "Downloading the migration plan..."
migctl migration get "$MIGRATION_JOB"
read -p "Please wait. Press any key... "$'\n' -n1 -s

echo "Below is the K8s CRD for migration object"
cat "$MIGRATION_JOB".yaml

#read -r -p "Do you want to update plan and add dataVolumes?  [y/N] " response
#case "$response" in
#    [yY][eE][sS]|[yY])
#        do_something
#        ;;
#    *)
#        do_something_else
#        ;;
#esac

# Optional step : modify my-migration plan
echo "(Optional) Modify the migration plan by editing my-migration.yaml:"

read -p "Open a new terminal and run the command below if anything changed... "$'\n' -n1 -s
echo "migctl migration update $MIGRATION_JOB --file $MIGRATION_JOB.yaml"

read -p "Did migration update successfully? After confirming press key to continue.."$'\n' -n1 -s

read -p "Ok to Proceed?. Press any key... "$'\n' -n1 -s

# Execute the VM migration plan
echo "Begin the VM migration: (Note this may take upto 10min)"
migctl migration generate-artifacts "$MIGRATION_JOB"

echo "Check the migration status:"
migctl migration status "$MIGRATION_JOB" -v
echo migctl migration status "$MIGRATION_JOB" -v
read -p "Please wait. Press any key... "$'\n' -n1 -s

echo "Check the migration status:"
echo migctl migration status "$MIGRATION_JOB" -v

read -p "Please wait for migration to complete. Press any key... "$'\n' -n1 -s

#Deploying the migrated workload
#Once the migration is complete, get the generated YAML artifacts
echo "Getting generated artefacts for $MIGRATION_JOB..."
migctl migration get-artifacts "$MIGRATION_JOB"

#-----------------------------------------------------------------------------------
# Final step: Deployment
echo "-----------------------------------------------------"
echo "Proceeding towards deployment...."

gcloud container clusters get-credentials cymbal-monolith-cluster --zone $ZONE --project ${PROJECT_ID}
kubectl apply -f deployment_spec.yaml --context=${CTX_4}
echo "replace all ledger service FQDNS with just  ledgermonolith-service:8080"
read -p "Hit ENTER to edit the config map"
kubectl edit configmap service-api-config --context=${CTX_4}


read -p "Hit ENTER to continue"
kubectl rollout restart deployment -n default --context=${CTX_4}

echo "PART 1 IS DONE!!!!"
