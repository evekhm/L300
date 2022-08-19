#! /bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR"/SET

#set -e # Exit if error is detected during pipeline execution
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

function t1_create_processing_cluster(){
  local TASK="Task 1"
  print "$TASK: Create a Migrate to Containers processing cluster"

  #Start the migration process by creating a single node processing cluster called m4a-processing
  #1. Create a processing cluster
  setup_network(){
    local NETWORK=default
    network=$(gcloud compute networks list --filter="name=(\"$NETWORK\" )" --format='get(NAME)' 2>/dev/null)
    if [ -z "$network" ]; then
        gcloud compute networks create $NETWORK --project="$PROJECT_ID" --subnet-mode=auto
    fi
  }
  setup_network
  echo "Creating a processing cluster..."
  gcloud container clusters create "$CLUSTER"  --project="$PROJECT_ID" \
    --zone="$ZONE" --machine-type e2-standard-4   --image-type ubuntu_containerd \
    --num-nodes "$NUM_NODES" --enable-stackdriver-kubernetes   \
    --subnetwork "projects/$PROJECT_ID/regions/$REGION/subnetworks/default"
  check_task "$TASK"
}

function t2_init_mgctl(){
  local TASK="Task 2"
  print "$TASK: Initialize Migrate to Containers on the processing cluster"

  # Stop VM
  echo "Stopping VM $SRC_VM_ID ..."
  gcloud compute instances stop "$SRC_VM_ID" --zone "$ZONE"

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

  echo "check in another terminal on progress by running"
  echo "migctl doctor"

  check_task "$TASK"
}

function t3_config_mgctl_for_ce(){
  local TASK="Task 3"
  print "$TASK: Configure Migrate to Containers for Compute Engine migrations"
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
  check_task "$TASK"
}

function t4_create_mgctl(){
  local TASK="Task 4"
  print "$TASK: Create a Migration for the Ledger Monolith VM"
  #Create a migration plan
  echo "Creating the migration plan..."
  migctl migration create "$MIGRATION_JOB" --source "$SRC_NAME"   --vm-id "$SRC_VM_ID" --type linux-system-container

  echo "check in another terminal on progress by running"
  echo " watch migctl migration status $MIGRATION_JOB"
  check_task "$TASK"
}

function t5_update_mgctl_plan(){
  local TASK="Task 5"
  print "$TASK: Update and finalize the Migration Plan"
  echo "Downloading the migration plan..."
  migctl migration get "$MIGRATION_JOB"
  read -p "Please wait. Press any key... "$'\n' -n1 -s

  echo "Below is the K8s CRD for migration object"
  cat "$MIGRATION_JOB".yaml

  echo "Updating the $MIGRATION_JOB.yaml"
  {
    echo
    echo dataVolumes:
    echo "  - folders:"
    echo "    - /var/lib/postgresql"
  } >> "$MIGRATION_JOB".yaml
  cat "$MIGRATION_JOB".yaml
  read -p "Does the plan look correct? After confirming press key to continue.."$'\n' -n1 -s
  migctl migration update $MIGRATION_JOB --file "$MIGRATION_JOB".yaml
  read -p "Did migration update successfully? After confirming press key to continue.."$'\n' -n1 -s
  check_task "$TASK"
}

function t6_gen_mgctl_artefacts(){
  local TASK="Task 6"
  print "$TASK: Generate the Migration artifacts"
  # Execute the VM migration plan
  echo "Begin the VM migration: (Note this may take upto 10min)..."
  migctl migration generate-artifacts "$MIGRATION_JOB"

  echo "Check the migration status:"
  migctl migration status "$MIGRATION_JOB" -v

  read -p "In a new terminal  run the command below and wait until it ends with Generate artifacts done... "$'\n' -n1 -s
  echo migctl migration status "$MIGRATION_JOB" -v
  read -p "Please wait till Artefacts are Generated. Press any key... "$'\n' -n1 -s
  check_task "$TASK"
}

function t7_deploy_artifacts(){
  local TASK="Task 7"
  print "$TASK: Deploy the generated container artifacts to the Cymbal Bank cluster"
  #Deploying the migrated workload
  #Once the migration is complete, get the generated YAML artifacts
  echo "Getting generated artefacts for $MIGRATION_JOB..."
  migctl migration get-artifacts "$MIGRATION_JOB" --output-directory "$DIR"

  gcloud container clusters get-credentials "$D_CLUSTER" --zone "$ZONE" --project "${PROJECT_ID}"
  kubectl apply -f "$DIR"/deployment_spec.yaml --context=${CTX_4}

  check_task "$TASK"
}

function t8_update_k8s_components(){
  local TASK="Task 8"
  print "$TASK: Update the existing Kubernetes components to point to the new containerized ledger service"
  echo "replace all ledger service FQDNS with just  ledgermonolith-service:8080"
  read -p "Hit ENTER to edit the config map"
  kubectl edit configmap service-api-config --context=${CTX_4}

  read -p "Hit ENTER to continue"
  kubectl rollout restart deployment -n default --context=${CTX_4}
  check_task "$TASK"
}

printh "Part 1: Use Migrate to Containers to containerize a VM and migrate the application to Anthos/GKE"
t1_create_processing_cluster
t2_init_mgctl
t3_config_mgctl_for_ce
t4_create_mgctl
t5_update_mgctl_plan
t6_gen_mgctl_artefacts
t7_deploy_artifacts
t8_update_k8s_components

echo "PART 1 IS DONE!!!!"
