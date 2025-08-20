制作 VM 镜像 (e2b-orch-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}) 如: `e2b-orch-2025-08-19-02-54-27`

https://console.cloud.google.com/compute/images?referrer=search&tab=images&authuser=1&project=e2b-proj&supportedpurview=project&inv=1&invt=Ab53GA

这个 packer 构建的 e2b-orch 镜像被用作整个集群基础设施的基础镜像，包括：
- Server 节点 (Nomad/Consul 服务器)
- Client 节点 (Nomad 客户端)
- API 节点 (API 服务)
- Build 节点 (构建任务)
- ClickHouse 节点 (数据库)
所有这些不同类型的节点都使用同一个基础镜像，然后通过不同的启动脚本来配置各自的角色和功能。

在各个集群子模块中（如 packages/cluster/client/main.tf），通过以下方式使用镜像：

```tf
# 获取镜像信息
data "google_compute_image" "source_image" {
  family = var.image_family
}

# 在实例模板中使用
resource "google_compute_instance_template" "client" {
  # ...
  disk {
    boot         = true
    source_image = data.google_compute_image.source_image.id
    # ...
  }
}
```