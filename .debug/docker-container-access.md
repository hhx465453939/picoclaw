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
- 镜像已安装 **openssh-server**，Gateway 启动时由 Dockerfile 内联 ENTRYPOINT（`/bin/sh -c "..."`）先启动 sshd 再 exec picoclaw gateway。
- 宿主机端口 **2222** 映射容器 22。本机容器：`ssh -p 2222 root@127.0.0.1`；NAS 容器：`ssh -p 2222 root@<NAS_IP>`。
- 认证：`.env` 中 `GATEWAY_SSH_ROOT_PASSWORD` 仅在容器启动时生效，修改后需 `docker compose up -d --force-recreate`；force-recreate 后若报 REMOTE HOST IDENTIFICATION HAS CHANGED，需 `ssh-keygen -f ~/.ssh/known_hosts -R '[127.0.0.1]:2222'`（或对应 IP）再连。完整流程见 docs/DEPLOYMENT-NAS-FEISHU.md §6.5。

## 注意事项
- 容器内已预装 **openssh-client**（`ssh`/`scp`/`sftp`），可在 `docker exec` 或 SSH 进容器后使用。
- 容器未预装 `curl`/`wget`，Agent 内若需上传文件到飞书等，需走应用层 API 或宿主机侧协助。
- 若需长期从宿主机直接访问工作区文件，可改为在 docker-compose 中把 `picoclaw-workspace` 改为 bind mount 到宿主机目录（例如 `./workspace:/root/.picoclaw/workspace`），便于用 Samba 在 Windows 下直接浏览（需评估备份与多实例隔离）。

## Debug 历史
- 2026-02-14 用户问如何访问项目 Docker 容器内文件；整理 exec / cp / volume 三种方式并写入本记录与 DEPLOYMENT-NAS-FEISHU.md §6.4。
- 2026-02-14 在 Dockerfile 运行时阶段加入 openssh-client，便于在容器内使用 ssh/scp/sftp 管理远程文件与运行配置；.debug 与部署文档同步说明。
- 2026-02-14 实现从本机 SSH 登录到容器：Dockerfile 增加 openssh-server、entrypoint-gateway.sh、sshd 配置；docker-compose 暴露 2222:22、ROOT_PASSWORD/env；新增 DEPLOYMENT-NAS-FEISHU §6.5 与 .env.example 说明。
- 2026-02-14 修复 Gateway 容器反复重启：入口脚本中 sshd 改为 `sshd || true` 避免 sshd 失败导致容器退出；Dockerfile 中 COPY 后 `sed -i 's/\r$//'` 剥离 CRLF，避免 Windows/Samba 换行符导致脚本执行失败；部署文档 §6.5 增加“容器反复重启”排查步骤（docker compose logs）。
- 2026-02-14 修复 exec /entrypoint-gateway.sh: no such file or directory：根因为 COPY 自 Samba/Windows 的脚本带 CRLF，shebang 被读成 `#!/bin/sh\r`，内核找不到解释器。改为在 Dockerfile 内用 RUN cat << 'EOF' 直接生成入口脚本，不再 COPY 宿主机文件，镜像内恒为 LF。
- 2026-02-14 若 heredoc 构建后仍报同一错误（可能为 Docker 版本/构建环境对 heredoc 处理不一致）：改为不依赖任何脚本文件，使用 ENTRYPOINT ["/bin/sh", "-c", "内联逻辑", "sh"] + CMD ["gateway"]，入口逻辑直接写在 exec 形式中，彻底避免脚本文件与 shebang。
- 2026-02-14 修复 gateway 只打印 Usage 后退出：sh -c "script" sh gateway 中 $1=gateway，误用 shift 导致 $@ 被清空；去掉 shift，保留 exec picoclaw "$@" 以正确传入 gateway。
- 2026-02-14 SSH 密码登录 Permission denied：说明 GATEWAY_SSH_ROOT_PASSWORD 仅在容器启动时由 entrypoint 执行 chpasswd；修改 .env 后需 `docker compose up -d --force-recreate` 才生效。部署文档 §6.5 补充“修改密码后须重建容器”及“密码正确仍 Permission denied”排查（force-recreate、或 exec chpasswd 验证）。
- 2026-02-14 SSH “REMOTE HOST IDENTIFICATION HAS CHANGED”：force-recreate 后容器重新生成 SSH host key，需 `ssh-keygen -f ~/.ssh/known_hosts -R '[127.0.0.1]:2222'` 删除旧条目再连。部署文档 §6.5 补充该排查。
- 2026-02-14 文档与操作流程对齐：在 §6.5 增加「正确操作流程（推荐顺序）」五步（设密码→build/up 或 force-recreate→按需删 known_hosts→ssh 连接→登录后路径）；步骤二区分「Gateway 在 NAS」与「Gateway 在本机」；.debug 中 SSH 入口改为“Dockerfile 内联 ENTRYPOINT”，并写明密码/known_hosts 注意点。
