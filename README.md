```
curl -O https://raw.githubusercontent.com/ziqing888/hyperlane/refs/heads/main/hyperlane.sh && chmod +x hyperlane.sh && ./hyperlane.sh

```
## 脚本主要功能

### 依赖安装
自动更新系统包，并安装常用工具、Docker、Python 等必要组件。如果已安装则跳过相应步骤。

### 自动检测 GPU 与端口
脚本会自动检测是否存在 NVIDIA GPU（启用 `runtime: nvidia`），并检测默认 FastAPI 映射端口（8080）是否被占用；如被占用，则自动寻找下一个可用端口。

### 仓库克隆与配置
脚本支持自动克隆或更新 RL Swarm 仓库，并生成配置文件 `docker-compose.yaml`。

### 容器启动与日志查看
脚本提供启动容器和实时查看日志的功能，让你能直观监控 RL 节点及 Web UI 的运行状态。

## 运行后注意事项

### 启动后容器日志
容器启动后，部分服务可能在后台运行。你可以在脚本主菜单中选择“查看日志”来实时监控各个服务的运行状态。

### Web UI 访问
- 如果默认端口 8080 被占用，脚本会自动调整为例如 8081。
- 访问地址示例：`http://<你的IP>:8081/`。

### 退出日志查看
在日志界面按 `Ctrl+C` 后，脚本会提示按回车返回主菜单。
