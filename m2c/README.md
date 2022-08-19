# Migrate to containers 

```shell
git clone https://github.com/evekhm/L300.git
cd L300
```

## [Qwiklab](https://www.cloudskillsboost.google/catalog_lab/2444) 

### Init
```shell
source m2c/SET_lab
```

### Create the source Compute Engine
```shell
create_source_vm.sh
```

In the Cloud Console navigate to [Compute Engine > VM instances](https://console.cloud.google.com/compute/instances) and locate the row for the instance you created and copy the External IP address.
Paste the instance's IP address to your browser address bar. Prefix it with http://.

### Migrate the VM

- Create Migration Plan
    ```shell
    . . m2c/create_plan.sh
    ```
- Execute Migration Plan
    ```shell
    . . m2c/doit.sh
    ```

## CEPF300
### Init
```shell
source m2c/SET
```
### Migrate the VM

- Execute Migration Plan
    ```shell
    . . m2c/doit.sh
    ```
