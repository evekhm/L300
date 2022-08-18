# Migrate to containers 

## [Qwiklab](https://www.cloudskillsboost.google/catalog_lab/2444) 

### Init

```shell
git clone https://github.com/evekhm/L300.git
cd L300/migrate4containers
```

```shell
source SET_lab
```

### Create the source Compute Engine
```shell
create_source_vm.sh
```

In the Cloud Console navigate to [Compute Engine > VM instances](https://console.cloud.google.com/compute/instances) and locate the row for the instance you created and copy the External IP address.

Paste the instance's IP address to your browser address bar. Prefix it with http://.

### Migrate the VM

- Stop VM
- Create Migration Plan
    ```shell
    . create_plan.sh
    ```
- Execute Migration Plan
    ```shell
    . migrate.sh
    ```

## CEPF300