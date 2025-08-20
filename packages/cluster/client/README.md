
> client cluster 使用 Firecracker 虚拟机执行沙箱工作负载。


它支持基于 CPU 利用率的 auto scaler [./main.tf#L18](./main.tf#L18) --> instance group manager [./main.tf#L39](./main.tf#L39) --> instance template [./main.tf#L94](./main.tf#L94)


instance 包括用于缓存的专用存储: [./main.tf#L18](./main.tf#L18)

通过 startup_script 初始化 instance