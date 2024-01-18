# How to setup Bigquery, Composer and DBT on GCP

## 1. Set up service accounts

- Create a new service account for Bigquery
   1. In IAM page, create a service account to run bigquery jobs from GCE instance.
      - The service account needs to have the following roles
         - ```BigQuery Data Editor```
         - ```BigQuery Job User```

   2. Create a key for the created service account which will be needed to run a bigquery job from DBT running on a GCE instance.

- Edit a service account for GCE which is automatically created when you create the GCE instance. 
  - In IAM page, edit the service account to have the following role. This is needed to create a dataset from this instance. This is not for the DBT tasks.
    - ```BigQuery Data Editor```

## 2. Create a GCE instance

1. Enable GCE(Compute Engine) API if not

2. Create a new instance
   - Need to set "Cloud API access scopes" to access bigquery from GCE
     - Set "Enable" for BigQuery in Cloud API access scopes.

3. Setup DBT environment

    ```[bash]
    # Install python3
    sudo apt upgrade -y
    sudo apt install -y python3-pip python3-venv git
    python3 -m venv venv
    source ./venv/bin/activate
    pip install dbt-core
    pip install dbt-bigquery

    # Copy the key to a folder on the GCE instance.
    mkdir ~/service_account_keys
    nano ~/service_account_keys/bigquery_crud.json

    # Create a DBT project
    mkdir dbt_pj
    cd dbt_pj
    dbt init sample_pj

    # Check the profile.yml
    cat ~/.dbt/profile.yml

    # sample_pj:
    # outputs:
    #     dev:
    #     dataset: dbt_test
    #     job_execution_timeout_seconds: 600
    #     job_retries: 1
    #     keyfile: ~/dbt_pj/service_account_keys/bigquery_crud.json
    #     location: us-central1
    #     method: service-account
    #     priority: interactive
    #     project: <project_id>
    #     threads: 1
    #     type: bigquery
    # target: dev
    ```

### 2-1. Run DBT command from shell script

1. Upload the following files to GCS
   - ```dbt-bigquery-cloud-composer-tutorial/dbt_master/dbt_debug.sh```
   - ```dbt-bigquery-cloud-composer-tutorial/dbt_master/dbt_run.sh```

2. Copy the dbt_debug.sh and dbt_run.sh files into the GCE instance from GCS bucket.

   ```[bash]
   # Example, run the command below from dbt-master instance.
   gsutil cp gs://dbt-bigquery-tutorial/dbt_debug.sh ~/dbt_pj/test/
   gsutil cp gs://dbt-bigquery-tutorial/dbt_run.sh ~/dbt_pj/test/
   ```

## 3. Set up Bigquery

1. Enable Bigquery API if not

2. Create a dataset from terminal from the GCE instance or local.

    ```[bash]
    bq --location=us-central1 --project_id=<project_id> mk \
        --dataset \
        --default_table_expiration=`expr 3600 \* 24 \* 7` \
        --description="sample table for dbt tutorial" \
        --label=dbt:sample \
        --max_time_travel_hours=`expr 24 \* 3` \
        --storage_billing_model=LOGICAL \
        dbt_test
    ```

    - If you got this error, please check the link
      - "BigQuery error in mk operation: Insufficient Permission"
      - <https://groups.google.com/g/gce-discussion/c/KowRiqKyhyQ?pli=1>

## 4. Check if DBT runs properly

1. Login to the GCE instance

2. Execute the dbt_debug.sh and dbt_run.sh

    ```[bash]
    sh ~/dbt_pj/test/dbt_debug.sh
    sh ~/dbt_pj/test/dbt_run.sh
    ```

## 5. Set up Composer

1. Enable Cloud Composer API if not

2. Add role to the service account created when you created the GCE instance to create a composer.
   - Target service account name
     - ```<random_id>-compute@developer.gserviceaccount.com```
   - Role name
     - ```Cloud Composer v2 API Service Agent Extension```

3. Create composer environment
   - Choose "Composer 2". ("Composer 1" is also okay)

4. Put the dag file (dbt_debug.py) to the dag folder on GCS.
   - Open the Dog folder on Cloud Storage
     - The link of the Cloud Storage can be found from composer console.
   - From the Cloud Storage web UI, upload the dag (dbt_debug.py) to the dag folder.
     - In my case, the file path is;

         ```[txt]
         gs://us-central1-my-composer-v1-4c3a9a53-bucket/dags/dbt_debug.py
         ```

         The initial dag file (airflow_monitoring.py) should be in the same folder.

         ```[txt]
         gs://us-central1-my-composer-v1-4c3a9a53-bucket/dags/airflow_monitoring.py
         ```

5. Create a SSH key to use SSHOperator to run DBT task from the composer. Since we cannot get a public key in the cloud composer directly, a new ssh key needs to be created in the GCE instance where the composer wants to access and copy the private key to a folder where the composer can access.
   - Create a new SSH key in GCE instance (dbt-master)

      ```[bash]
      # Run the command from GCE instance
      # The key name should not be "id_ras", I'd recommend it should be like "id_rsa_composer" since this key is not for the GCE instance.

      ssh-keygen

      ls -al ~/.ssh
      # output
      drwx------  2 dbt_user dbt_user 4096 Jan 18 01:04 .
      drwxr-xr-x 12 dbt_user dbt_user 4096 Jan 18 01:43 ..
      -rw-------  1 dbt_user dbt_user 2655 Jan 18 01:04 authorized_keys
      -rw-------  1 dbt_user dbt_user 2622 Jan 17 06:13 id_rsa_composer
      -rw-r--r--  1 dbt_user dbt_user  580 Jan 17 06:13 id_rsa_composer.pub
      -rw-r--r--  1 dbt_user dbt_user  444 Jan 17 03:46 known_hosts
      ```

      Created the "id_rsa_composer" and "id_rsa_composer.pub" keys now.

   - Create a new folder in the dags folder to store the ssh private key.

        ```[txt]
        # Create the following folder from GCS console.
        gs://us-central1-my-composer-v1-4c3a9a53-bucket/dags/ssh_config
        ```

   - Copy the private key to a folder under the dag folder mounted to the composer.

        ```[bash]
        gsutil cp ~/.ssh/id_rsa_composer gs://us-central1-my-composer-v1-4c3a9a53-bucket/dags/ssh_config
        ```

### 5-1. Run the DAG (dbt_debug.py) from Airflow web UI

1. Open the Airflow web UI from the Composer console browser.

2. Click "Airflow webserver" on the console to open the Airflow web UI

3. Run the new dag, which the dag name is "run_dbt_by_ssh_operator"

   > NOTE: If the dag file updated in the previous is successfully uploaded to the specific dag folder, the dag name must be displayed. If it's not, try to upload the dag file again to the correct dag folder.

## Note

- All regions should be the same to prevent any issues.
  - e.g., us-central1
