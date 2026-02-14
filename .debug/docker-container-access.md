# Docker 容器内文件访问 Debug 记录

## 元信息
- 模块名称: docker-container-access
- 创建时间: 2026-02-14
- 最后更新: 2026-02-14
- 相关文件: docker-compose.yml, Dockerfile, docs/DEPLOYMENT-NAS-FEISHU.md
- 依赖模块: project-debug（运行上下文：NAS + ssh home_nas）
- 开发/部署文档路径: docs/DEPLOYMENT-NAS-FEISHU.md §6.4

## 运行上下文与测试规则
- 运行环境: NAS-Samba+SSH
- SSH 方式: `ssh home_nas`
- 远程项目路径: `/home/damncheater/Development/picoclaw`
- 验证方式: 在 NAS 上执行 docker 命令（可通过 `ssh home_nas "..."`）

## 上下文关系

- **容器名**: `picoclaw-gateway`（Gateway 长期运行服务）
- **工作目录**: 容器内 Agent 工作区为 `/root/.picoclaw/workspace`，项目产物如压缩包在 `/root/.picoclaw/workspace/projects/`（例如 `claw_family_health.tar.gz`）
- **卷挂载**: 命名卷 `picoclaw-workspace` 挂载到容器内 `/root/.picoclaw/workspace`，数据持久化在 Docker 卷中（不在宿主机项目目录下）

## 访问容器内文件的三种方式

### 1. docker exec：进入容器执行命令
在 NAS 上（或通过 SSH）执行：
```bash
# 进入项目目录（若需用 compose 上下文）
cd /home/damncheater/Development/picoclaw

# 在容器内执行单条命令
docker compose exec picoclaw-gateway ls -la /root/.picoclaw/workspace/projects/

# 启动交互式 shell（容器为 Alpine，默认 sh）
docker compose exec picoclaw-gateway sh
# 进入后可直接：ls、cat、cp 等操作容器内路径
```

### 2. docker cp：从容器复制文件到宿主机
```bash
# 从容器复制单个文件到当前目录
docker cp picoclaw-gateway:/root/.picoclaw/workspace/projects/claw_family_health.tar.gz ./

# 复制整个目录
docker cp picoclaw-gateway:/root/.picoclaw/workspace/projects ./projects-backup
```
复制到 NAS 后，若需传到本机 Windows，可用 SCP/Samba 或飞书/云盘等方式。

### 3. 查看卷在宿主机上的实际路径（仅查看，一般不直接改）
```bash
docker volume inspect picoclaw-workspace
```
其中 `Mountpoint` 为卷在 NAS 上的路径（通常需 root 或 docker 组权限才能直接读写）。

## 从本机 SSH 登录到容器（已启用）
- 镜像已安装 **openssh-server**，Gateway 启动时由 `docker/entrypoint-gateway.sh` 先启动 sshd 再运行 picoclaw。
- 宿主机端口 **2222** 映射容器 22。从本机登录：`ssh -p 2222 root@<NAS_IP>`。
- 认证：设置环境变量 `GATEWAY_SSH_ROOT_PASSWORD`（或在 `.env` 中）可密码登录；或挂载/写入 `authorized_keys` 公钥登录。详见 docs/DEPLOYMENT-NAS-FEISHU.md §6.5。

## 注意事项
- 容器内已预装 **openssh-client**（`ssh`/`scp`/`sftp`），可在 `docker exec` 或 SSH 进容器后使用。
- 容器未预装 `curl`/`wget`，Agent 内若需上传文件到飞书等，需走应用层 API 或宿主机侧协助。
- 若需长期从宿主机直接访问工作区文件，可改为在 docker-compose 中把 `picoclaw-workspace` 改为 bind mount 到宿主机目录（例如 `./workspace:/root/.picoclaw/workspace`），便于用 Samba 在 Windows 下直接浏览（需评估备份与多实例隔离）。

## Debug 历史
- 2026-02-14 用户问如何访问项目 Docker 容器内文件；整理 exec / cp / volume 三种方式并写入本记录与 DEPLOYMENT-NAS-FEISHU.md §6.4。
- 2026-02-14 在 Dockerfile 运行时阶段加入 openssh-client，便于在容器内使用 ssh/scp/sftp 管理远程文件与运行配置；.debug 与部署文档同步说明。
- 2026-02-14 实现从本机 SSH 登录到容器：Dockerfile 增加 openssh-server、entrypoint-gateway.sh、sshd 配置；docker-compose 暴露 2222:22、ROOT_PASSWORD/env；新增 DEPLOYMENT-NAS-FEISHU §6.5 与 .env.example 说明。
