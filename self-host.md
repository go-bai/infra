# Self-hosting E2B on Google Cloud

## Prerequisites

**Tools**

- [Packer](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli#installing-packer)
  - Used for building the disk image of the orchestrator client and server

- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) (v1.5.x)
  - We ask for v1.5.x because starting from v1.6 Terraform [switched](https://github.com/hashicorp/terraform/commit/b145fbcaadf0fa7d0e7040eac641d9aef2a26433) their license from Mozilla Public License to Business Source License.
  - The last version of Terraform that supports Mozilla Public License is **v1.5.7**
    - Binaries are available [here](https://developer.hashicorp.com/terraform/install/versions#binary-downloads)
      ```sh
      wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
      unzip terraform_1.5.7_linux_amd64.zip
      mv terraform /usr/bin/
      rm -rf terraform_1.5.7_linux_amd64.zip
      ```
    - You can also install it via [tfenv](https://github.com/tfutils/tfenv)
      ```sh
      brew install tfenv
      tfenv install 1.5.7
      tfenv use 1.5.7
      ```

- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install)
  - Used for managing the infrastructure on Google Cloud
  - Be sure to authenticate:
    ```sh
    gcloud auth login
    gcloud auth application-default login
    ```

- [Golang](https://go.dev/doc/install)

- [Docker](https://docs.docker.com/engine/install/)


**Accounts**

- Cloudflare account
- Domain on Cloudflare
- GCP account + project
- PostgreSQL database (Supabase's DB only supported for now)
  - Supabase 负责用户管理和 JWT 生成

**Optional**

Recommended for monitoring and logging
- Grafana Account & Stack (see Step 15 for detailed notes)
- Posthog Account

## Steps

Check if you can use config for terraform state management

1. Go to `console.cloud.google.com` and create a new GCP project
    > Make sure your Quota allows you to have at least 2500G for `Persistent Disk SSD (GB)` and at least 24 for `CPUs`
2. Create `.env.prod`, `.env.staging`, or `.env.dev` from [`.env.template`](.env.template). You can pick any of them. Make sure to fill in the values. All are required if not specified otherwise.
    > Get Postgres database connection string from your database, e.g. [from Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres#direct-connection): Create a new project in Supabase and go to your project in Supabase -> Settings -> Database -> Connection Strings -> Postgres -> Direct
    
    > Your Postgres database needs to have enabled IPv4 access. You can do that in Connect screen
3. Run `make switch-env ENV={prod,staging,dev}` to start using your env

先创建 bucket `gcloud storage buckets create gs://gobai-e2b-dev-state --location us-west1 --project gobai-e2b-dev --default-storage-class STANDARD  --uniform-bucket-level-access`

`make switch-env ENV=dev`

4. Run `make login-gcloud` to login to `gcloud`
5. Run `make init`. If this errors, run it a second time--it's due to a race condition on Terraform enabling API access for the various GCP services; this can take several seconds. A full list of services that will be enabled for API access:
   - [Secret Manager API](https://console.cloud.google.com/apis/library/secretmanager.googleapis.com)
   - [Certificate Manager API](https://console.cloud.google.com/apis/library/certificatemanager.googleapis.com)
   - [Compute Engine API](https://console.cloud.google.com/apis/library/compute.googleapis.com)
   - [Artifact Registry API](https://console.cloud.google.com/apis/library/artifactregistry.googleapis.com)
   - [OS Config API](https://console.cloud.google.com/apis/library/osconfig.googleapis.com)
   - [Stackdriver Monitoring API](https://console.cloud.google.com/apis/library/monitoring.googleapis.com)
   - [Stackdriver Logging API](https://console.cloud.google.com/apis/library/logging.googleapis.com)


- google_compute_firewall.internal_remote_connection_firewall_ingress
- google_compute_network.packer_network
- google_compute_subnetwork.packer_subnetwork

配置 PACKER_GITHUB_API_TOKEN 环境变量, 提升 github request 的 rate limit, 防止 GET https://api.github.com/repos/hashicorp/packer-plugin-googlecompute/git/matching-refs/tags: 403 API rate limit exceeded 错误

最终会制作出一个 VM image 模版, 用于创建 VM 实例

6. Run `make build-and-upload`

build 上传 docker image 到 GCP Artifact Registry (e2b-orchestration), 包括以下容器镜像和二进制文件(template-manager 等):

```bash
us-west1-docker.pkg.dev/gobai-e2b-dev/e2b-orchestration/clickhouse-migrator               latest                   89a6c0069c2a   6 hours ago     66.6MB
us-west1-docker.pkg.dev/gobai-e2b-dev/e2b-orchestration/docker-reverse-proxy              latest                   e40cbaec2609   6 hours ago     41.2MB
us-west1-docker.pkg.dev/gobai-e2b-dev/e2b-orchestration/client-proxy                      latest                   2e12a55ec9fb   6 hours ago     113MB
us-west1-docker.pkg.dev/gobai-e2b-dev/e2b-orchestration/db-migrator                       latest                   836c706b6021   6 hours ago     16.9MB
us-west1-docker.pkg.dev/gobai-e2b-dev/e2b-orchestration/api                               latest                   9bf740b31cf5   6 hours ago     
```

```bash
$ gsutil ls gs://gobai-e2b-dev-fc-env-pipeline
gs://gobai-e2b-dev-fc-env-pipeline/envd
gs://gobai-e2b-dev-fc-env-pipeline/orchestrator
gs://gobai-e2b-dev-fc-env-pipeline/template-manager
```

7. Run `make copy-public-builds`. This will copy kernel and rootfs builds for Firecracker to your bucket. You can [build your own](#building-firecracker-and-uffd-from-source) kernel and Firecracker roots.

复制了以下内容到自己的 bucket:

```bash
➜  infra git:(main) ✗ gsutil ls gs://e2b-prod-public-builds/kernels/ 
gs://e2b-prod-public-builds/kernels/vmlinux-6.1.102/
➜  infra git:(main) ✗ gsutil ls gs://e2b-prod-public-builds/firecrackers/       
gs://e2b-prod-public-builds/firecrackers/v1.10.1_1fcdaec/
gs://e2b-prod-public-builds/firecrackers/v1.12.1_d990331/
```

8. Run `make migrate`

数据库迁移:

```bash
2025/08/19 11:42:41 OK   20000101000000_auth.sql (577.84ms)
2025/08/19 11:42:41 OK   20000101000001_rls_for_migration_table.sql (560.81ms)
...
2025/08/19 11:43:05 goose: successfully migrated database to version: 20250802144312
Done
make[1]: Leaving directory '/root/ai/infra/packages/db'
```

9. Secrets are created and stored in GCP Secrets Manager. Once created, that is the source of truth--you will need to update values there to make changes. Create a secret value for the following secrets:
  - e2b-cloudflare-api-token
      > Get Cloudflare API Token: go to the [Cloudflare dashboard](https://dash.cloudflare.com/) -> Manage Account -> Account API Tokens -> Create Token -> Edit Zone DNS -> in "Zone Resources" select your domain and generate the token
  - e2b-grafana-api-key (optional) - read more in [grafana README](./terraform/grafana/README.md)
  - Posthog API keys for monitoring (optional)

更新 GCP Secrets Manager 中的 secret:
- e2b-cloudflare-api-token

10. Run `make plan-without-jobs` and then `make apply`

创建几个 cluster 的 GCE VM
创建 client 的 auto scaler
创建 LB
各种 google_compute_backend_service
在 cloudflare 中添加 DNS 记录, 一个 A 记录(record), 一个 CNAME 记录(auth)

11. Fill out the following secret in the GCP Secrets Manager:
  - e2b-supabase-jwt-secrets (optional / required to self-host the [E2B dashboard](https://github.com/e2b-dev/dashboard))
      > Get Supabase JWT Secret: go to the [Supabase dashboard](https://supabase.com/dashboard) -> Select your Project -> Project Settings -> Data API -> JWT Settings
  - e2b-postgres-connection-string
    > This is the same value as for the `POSTGRES_CONNECTION_STRING` env variable.

更新 GCP Secrets Manager 中的 secret:
- e2b-postgres-connection-string

12. Run `make plan` and then `make apply`. Note: This will work after the TLS certificates was issued. It can take some time; you can check the status in the Google Cloud Console

13. Setup data in the cluster by following one of the two 
    - `make prep-cluster` in `packages/shared` to create an initial user, etc. (You need to be logged in via [`e2b` CLI](https://www.npmjs.com/package/@e2b/cli)). It will create a user with same information (access token, api key, etc.) as you have in E2B. 
    - You can also create a user in database, it will automatically also create a team, an API key and an access token. You will need to build template(s) for your cluster. Use [`e2b` CLI](https://www.npmjs.com/package/@e2b/cli?activetab=versions)) and run `E2B_DOMAIN=<your-domain> e2b template build`.

```bash
brew install e2b
e2b auth login
...
```

### Interacting with the cluster

#### SDK
When using SDK pass domain when creating new `Sandbox` in JS/TS SDK
```js
import { Sandbox } from "@e2b/sdk";

const sandbox = new Sandbox({
  domain: "<your-domain>",
});
```

or in Python SDK

```python
from e2b import Sandbox

sandbox = Sandbox(domain="<your-domain>")
```

#### CLI
When using CLI you can pass domain as well
```sh
E2B_DOMAIN=<your-domain> e2b <command>
```

#### Monitoring and logging jobs

To access the nomad web UI, go to https://nomad.<your-domain.com>. Go to sign in, and when prompted for an API token, you can find this in GCP Secrets Manager. From here, you can see nomad jobs and tasks for both client and server, including logging.

To update jobs running in the cluster look inside packages/nomad for config files. This can be useful for setting your logging and monitoring agents.

### Troubleshooting

If any problems arise, open [a Github Issue on the repo](https://github.com/e2b-dev/infra/issues) and we'll look into it.

---

### Building Firecracker and UFFD from source

E2B is using [Firecracker](https://github.com/firecracker-microvm/firecracker) for Sandboxes.
You can build your own kernel and Firecracker version from source by running `make build-and-upload-fc-components`

- Note: This needs to be done on a Linux machine due to case-sensitive requirements for the file system--you'll error out during the automated git section with a complaint about unsaved changes. Kernel and versions could alternatively be sourced elsewhere.

### Make commands cheat sheet

- `make init` - setup the terraform environment
- `make plan` - plans the terraform changes
- `make apply` - applies the terraform changes, you have to run `make plan` before this one
- `make plan-without-jobs` - plans the terraform changes without provisioning nomad jobs
- `make plan-only-jobs` - plans the terraform changes only for provisioning nomad jobs
- `make destroy` - destroys the cluster
- `make version` - increments the repo version
- `make build-and-upload` - builds and uploads the docker images, binaries, and cluster disk image
- `make copy-public-builds` - copies the old envd binary, kernels, and firecracker versions from the public bucket to your bucket
- `make migrate` - runs the migrations for your database
- `make login-gcloud` - logs in to gcloud
- `make switch-env ENV={prod,staging,dev}` - switches the environment
- `make import TARGET={resource} ID={resource_id}` - imports the already created resources into the terraform state
- `make setup-ssh` - sets up the ssh key for the environment (useful for remote-debugging)
- `make connect-orchestrator` - establish the ssh connection to the remote orchestrator (for testing API locally)

---

## Google Cloud Troubleshooting
**Quotas not available** 

If you can't find the quota in `All Quotas` in GCP's Console, then create and delete a dummy VM before proceeding to step 2 in self-deploy guide. This will create additional quotas and policies in GCP 
```
gcloud compute instances create dummy-init   --project=YOUR-PROJECT-ID   --zone=YOUR-ZONE   --machine-type=e2-medium   --boot-disk-type=pd-ssd   --no-address
```
Wait a minute and destroy the VM:
```
gcloud compute instances delete dummy-init --zone=YOUR-ZONE --quiet
```
Now, you should see the right quota options in `All Quotas` and be able to request the correct size. 


# DEBUG

## orch-server VM 的 logs:

```bash
/var/log/user-data.log 
/opt/nomad/log/nomad-stdout.log
/opt/nomad/log/nomad-error.log 
```

## VM 串口日志

```bash
gcloud compute --project=gobai-e2b-dev instances get-serial-port-output gobai-dev-e2b-orch-client-fzqw --zone=us-west1-a --port=1
```

## vm template 问题

> build cluster 和 client cluster 的 instance template 指定了 min_cpu_platform 为 "Intel Skylake", 所以不能使用 e2-standard-4 的机器, 需要使用 n1-standard-4 的机器, 申请不下来

## glibc 版本问题

构建 template manager 和 orchestrator 的二进制时使用的 golang:1.24 基础镜像，并且 CGO_ENABLED=1 编译，导致依赖了高版本 glibc 不能在 ubuntu22.04 虚拟机直接 raw_exec 执行

> 现在已经修复, 改为了使用 golang:1.24-bookworm 基础镜像

TODO:

还差 `make prep-cluster` 的子步骤 `make build-base-template` 没有完成