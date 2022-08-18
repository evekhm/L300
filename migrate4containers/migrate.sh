#Migrate the VM using the migration plan
#This command will migrate the VM and generate artifacts you can use to deploy the workload:
migctl migration generate-artifacts "$MIGRATION_JOB"

#check its status
migctl migration status "$MIGRATION_JOB" -v

#Deploying the migrated workload
#Once the migration is complete, get the generated YAML artifacts
migctl migration get-artifacts "$MIGRATION_JOB"