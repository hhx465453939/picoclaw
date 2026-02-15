# PicoClaw 在本地 NAS（Ubuntu）上的部署与飞书内网聊天配置指南

> 适用场景：代码存放在 NAS（Ubuntu 环境）上，通过 `ssh home_nas` 进入远程服务器进行编译、测试与部署，并在内网环境下通过 **飞书机器人** 与 PicoClaw 进行聊天。

---

## 1. 整体架构与工作模式

- **运行环境**：NAS 上的 Ubuntu（或等价 Linux 环境），通过 `ssh home_nas` 登录。
- **应用形态**：PicoClaw 以 **Gateway 模式** 长期运行，接收来自飞书机器人的消息。
- **飞书接入方式**：使用飞书官方 **WebSocket 事件订阅** 能力，PicoClaw 通过 WebSocket 主动连出飞书云端：
  - NAS 只需要 **能访问公网的 443 端口**（访问飞书与 LLM 提供商 API）。
  - **不需要在内网开放公网端口、也不需要反向代理/内网穿透**。
- **LLM 提供方**：可选 OpenRouter / Zhipu / OpenAI / Anthropic / Gemini / Groq 等，在 `config.json` 中配置。

推荐在 NAS 上使用 **Docker Compose + `picoclaw-gateway`** 方式部署，统一管理配置与数据。

---

## 2. 环境前提与准备

### 2.1 NAS / Ubuntu 前提

在 NAS 上通过 `ssh home_nas` 进入 Ubuntu 环境后，确保：

- 已安装：
  - `git`
  - `docker` 与 `docker compose`（或 `docker compose plugin`）
- 网络能够访问：
  - `https://open.feishu.cn` / `https://open.larksuite.com`
  - 所选 LLM 服务商（如 `https://openrouter.ai`、`https://open.bigmodel.cn` 等）

如需安装 Docker（仅参考）：

```bash
ssh home_nas

sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"
# 重新登录一次 shell 以生效 docker 组
```

### 2.2 代码路径约定

本指南默认代码在 NAS 上的路径为：

```bash
/home/damncheater/Development/picoclaw
```

对应本地 Windows 上的 Samba 映射路径为：

```text
z:\home\damncheater\Development\picoclaw
```

如路径实际不同，请在后续命令中替换为真实路径。

---

## 3. 从源码构建与基础测试（Go Native）

> 该步骤用于验证代码在 NAS 上可以顺利编译和通过基础测试，**推荐在 Docker 部署前先执行一次**。

1. 登录 NAS 并进入项目目录：

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw
```

2. 确保安装 Go（要求 `go 1.25+`）：

```bash
go version
```

如未安装，可按官方文档安装 Go（略）。

3. 运行 Go 单元测试：

```bash
go test ./...
```

4. 使用 Makefile 构建二进制：

```bash
make build
```

执行完成后，二进制位于：

```bash
build/picoclaw-<平台>-<架构>
build/picoclaw           # 指向当前平台的二进制软链接
```

如需在 NAS 上直接安装到 `~/.local/bin`（方便裸机运行）：

```bash
make install
# 安装后可直接使用 `picoclaw` 命令
```

> 说明：后续章节推荐使用 Docker Compose 部署 Gateway；上述 native 构建可作为编译/测试验证步骤。

---

## 4. Docker Compose 部署到 NAS（推荐）

### 4.1 准备配置文件

1. 登录 NAS 并进入项目目录：

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw
```

2. 创建运行时配置 `config/config.json`（如尚未存在）：

```bash
mkdir -p config
cp config/config.example.json config/config.json
```

3. 编辑 `config/config.json`，至少需要：

- **选择 LLM 提供方**（providers）：

```jsonc
{
  "providers": {
    "openrouter": {
      "api_key": "sk-or-v1-xxx",
      "api_base": ""
    },
    "zhipu": {
      "api_key": "YOUR_ZHIPU_API_KEY",
      "api_base": ""
    }
    // 其它 provider 可按需配置
  }
}
```

根据实际使用的服务商填入对应 API Key。

- **启用 Feishu 渠道**（见下一节“飞书应用与内网聊天配置”）：

```jsonc
{
  "channels": {
    "feishu": {
      "enabled": true,
      "app_id": "cli_xxx",
      "app_secret": "xxx",
      "encrypt_key": "your_encrypt_key",
      "verification_token": "your_verification_token",
      "allow_from": ["user_or_open_id_1", "user_or_open_id_2"]
    }
  }
}
```

4. 可选：使用 `.env` 传入部分敏感配置（如 LLM API Key），参考 `.env.example`：

```bash
cp .env.example .env
vim .env  # 按需填入 OPENROUTER_API_KEY / ZHIPU_API_KEY 等
```

> 注：当前项目主要使用 `~/.picoclaw/config.json` 中的配置，`.env` 是补充渠道。

### 4.2 构建 Docker 镜像

在项目根目录执行：

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw

docker compose --profile gateway build
```

构建过程：

- 使用 `Dockerfile` 以多阶段方式构建：
  - 第一阶段使用 `golang:1.25-alpine` 编译二进制（执行 `make build`）。
  - 第二阶段使用 `alpine:3.21` 打包最小运行时镜像，并将内置 `skills` 复制到容器内。

### 4.3 启动 Gateway（长驻服务）

在正确配置好 `config/config.json` 和（可选）`.env` 之后：

```bash
docker compose --profile gateway up -d
```

查看日志：

```bash
docker compose logs -f picoclaw-gateway
```

常见正常日志包括：

- Agent 初始化信息（工具数量、skills 数量）。
- 各渠道初始化日志，如：
  - `Feishu channel enabled successfully`
  - `Feishu channel started (websocket mode)`
- `Gateway started on 0.0.0.0:18790`

停止服务：

```bash
docker compose --profile gateway down
```

---

## 5. 飞书应用与内网聊天配置方案

本节给出一个 **在内网 NAS 上运行 PicoClaw + 飞书聊天机器人** 的完整方案，基于项目中 `pkg/channels/feishu.go` 的实现（WebSocket 事件订阅模式）。

### 5.1 在飞书开放平台创建自建应用

1. 登录飞书开放平台：
   - 管理后台入口：`https://open.feishu.cn`（或国际版 `https://open.larksuite.com`）。
2. 创建 **企业自建应用**：
   - 应用类型选择：**企业自建应用**。
   - 填写应用名称、描述、图标等基础信息。
3. 在应用能力中启用：
   - **机器人（Bot）能力**。
   - **事件订阅**（后续会在事件订阅页面中选择「长连接 / WebSocket」方式接收事件，而不是 URL 订阅）。

### 5.2 启用「长连接 / WebSocket」事件订阅（适配内网 NAS）

PicoClaw 中 Feishu 渠道的实现为 **WebSocket 模式**：

```go
// 摘自 pkg/channels/feishu.go
dispatcher := larkdispatcher.NewEventDispatcher(c.config.VerificationToken, c.config.EncryptKey).
    OnP2MessageReceiveV1(c.handleMessageReceive)

c.wsClient = larkws.NewClient(
    c.config.AppID,
    c.config.AppSecret,
    larkws.WithEventHandler(dispatcher),
)
```

这与飞书官方文档中「使用长连接接收事件」是一致的（参见飞书开放平台文档：`使用长连接接收事件` 一节），这意味着：

- NAS 上的进程主动与飞书云端建立 WebSocket 连接。
- 不需要公网可达的回调 URL，也不需要配置端口映射或内网穿透。

在飞书开放平台中（Web 控制台）通常会看到两种事件接收方式：**请求网址 (URL 订阅)** 和 **长连接 (长连接 / WebSocket)**。本项目只需要长连接，不需要配置对外可访问的 URL：

1. 进入应用的「事件订阅」配置页面。
2. 在「事件接收方式」或类似位置选择 **长连接 / 使用长连接接收事件 / WebSocket**（名称可能略有差异，以飞书当前界面为准），**不要选择仅依赖 URL 的请求网址模式**。
3. 勾选需要的事件类型，至少包括：
   - 私聊消息事件：`im.message.receive_v1`（或等价命名）。
4. 保存配置。

### 5.3 获取飞书应用凭据并写入 config.json

在飞书应用详情中找到：

- `App ID`（应用 ID）
- `App Secret`（应用密钥）
- `Encrypt Key`（加密密钥）
- `Verification Token`（校验 Token）

将上述字段填入 `config/config.json` 中的 `channels.feishu` 段：

```jsonc
{
  "channels": {
    "feishu": {
      "enabled": true,
      "app_id": "cli_xxx",
      "app_secret": "xxx",
      "encrypt_key": "your_encrypt_key",
      "verification_token": "your_verification_token",
      "allow_from": ["user_or_open_id_1", "user_or_open_id_2"]
    }
  }
}
```

#### 关于 `allow_from` 控制

PicoClaw 在渠道层会根据 `allow_from` 控制哪些用户可以与机器人对话：

- 填入 Feishu 的 **用户 ID / OpenID / UnionID**（任一即可，按实际部署策略选择）。
- 示例策略：
  - 仅允许自己：`["your_user_id"]`
  - 允许多个内部测试账号：`["userid_1", "userid_2"]`
  - 若留空数组 `[]`，可视为不限制（具体行为参考 `BaseChannel` 的实现）。

### 5.4 内网聊天消息流程

消息收发流程简要如下：

1. 用户在飞书客户端向机器人发送消息。
2. 飞书云端将事件通过 **WebSocket** 推送到运行在 NAS 上的 `picoclaw-gateway`：
   - `FeishuChannel.handleMessageReceive` 解析消息内容与 sender 信息。
   - 通过内部消息总线 `bus.MessageBus` 投递到 Agent Loop。
3. PicoClaw Agent 使用配置好的 LLM Provider（如 OpenRouter/Zhipu）生成回复。
4. `FeishuChannel.Send` 使用 SDK 的 `Im.V1.Message.Create` 接口将回复发回飞书会话。

NAS 只需：

- 能访问飞书开放平台的 WebSocket 终端。
- 能访问 LLM 服务商的 HTTP API。

无需：

- 对外暴露 HTTP/HTTPS 端口。
- 配置反向代理或内网穿透。

---

## 6. 典型运维命令（在 NAS 上）

### 6.1 查看 Gateway 运行状态

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw

docker compose ps
docker compose logs -f picoclaw-gateway
```

### 6.2 更新代码并重启服务

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw

git pull
docker compose --profile gateway build
docker compose --profile gateway up -d
```

### 6.3 修改配置后重启

1. 修改 `config/config.json` 中的 LLM 或飞书配置。
2. 重启容器：

```bash
docker compose --profile gateway restart picoclaw-gateway
```

### 6.4 容器时区（北京时间）

镜像与 Compose 中已设置 **TZ=Asia/Shanghai**，容器内时间与 **北京时间** 一致，影响：

- Agent 系统提示中的 **Current Time**
- Cron 定时任务的执行时间
- Heartbeat 等时间戳

如需改为其他时区，在 `docker-compose.yml` 的 `picoclaw-gateway` 的 `environment` 中修改或新增 `TZ`，例如：`TZ=America/New_York`。修改后执行 `docker compose --profile gateway up -d --force-recreate` 使环境变量生效。

### 6.5 访问容器内文件（工作区、打包产物等）

Agent 生成的项目压缩包等位于容器内 `/root/.picoclaw/workspace/projects/`，该目录由 Docker 命名卷 `picoclaw-workspace` 持久化。可用以下方式访问：

**方式一：在容器内执行命令（推荐先查看内容）**

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw

# 列出工作区项目文件
docker compose exec picoclaw-gateway ls -la /root/.picoclaw/workspace/projects/

# 进入容器 shell 后自行 ls/cat/cp 等
docker compose exec picoclaw-gateway sh
```

**方式二：把文件从容器复制到 NAS 当前目录**

```bash
# 复制单个压缩包到当前目录
docker cp picoclaw-gateway:/root/.picoclaw/workspace/projects/claw_family_health.tar.gz ./

# 复制整个 projects 目录
docker cp picoclaw-gateway:/root/.picoclaw/workspace/projects ./projects-backup
```

复制到 NAS 后，可通过 SCP、Samba 或云盘等方式传到本机。如需查看卷在宿主机上的实际路径，可执行：`docker volume inspect picoclaw-workspace`（其中 `Mountpoint` 即宿主机路径，通常需相应权限才能直接访问）。

镜像内已预装 **openssh-client**（`ssh`/`scp`/`sftp`）。进入容器后（`docker compose exec picoclaw-gateway sh`）可直接使用这些命令连接其他主机、拉取或推送文件。

### 6.6 从本机 SSH 登录到 Gateway 容器

Gateway 容器内已运行 **sshd**，宿主机映射端口 **2222 → 22**。可从本机（或 NAS 本机）直接 SSH 进容器，便于管理工作区文件与运行配置。

**正确操作流程（推荐按此顺序）**

1. **设置密码**：在项目目录的 `.env` 中写 `GATEWAY_SSH_ROOT_PASSWORD=你的密码`（无空格、无引号）。
2. **启动或重建容器**：
   - 首次：`docker compose --profile gateway build` 后执行 `docker compose --profile gateway up -d`。
   - 修改过 `.env` 中的密码后：`docker compose --profile gateway up -d --force-recreate`（否则新密码不生效）。
3. **处理主机密钥（仅当曾连过且做过 force-recreate 时）**：若 SSH 报 “REMOTE HOST IDENTIFICATION HAS CHANGED”，先执行  
   `ssh-keygen -f ~/.ssh/known_hosts -R '[127.0.0.1]:2222'`（本机容器）或把 `127.0.0.1` 换成 NAS IP（远程容器）。
4. **连接**：`ssh -p 2222 root@127.0.0.1`（Gateway 在本机时）或 `ssh -p 2222 root@<NAS_IP>`（Gateway 在 NAS 时）；首次提示信任主机密钥输入 `yes`，再输入 `.env` 中的密码。
5. **登录后**：工作区为 `/root/.picoclaw/workspace`，项目压缩包在 `/root/.picoclaw/workspace/projects/`。

**步骤一：设置登录方式（二选一或同时用）**

- **密码登录**：在项目目录下创建或编辑 `.env`，设置：
  ```bash
  GATEWAY_SSH_ROOT_PASSWORD=你设置的密码
  ```
  **重要**：密码只在容器**启动时**由入口脚本写入（chpasswd）。修改 `.env` 后必须**重建容器**才能生效：`docker compose --profile gateway up -d --force-recreate`。若只 `up -d` 且容器已存在，不会重新读 `.env` 设密码。
- **公钥登录（推荐）**：把本机公钥写入容器内 root 的 `authorized_keys`。
  - 一次性写入（在 NAS 上执行）：先 `ssh home_nas`，再在项目目录执行  
    `docker compose exec picoclaw-gateway sh -c 'mkdir -p /root/.ssh && cat >> /root/.ssh/authorized_keys'`  
    然后粘贴本机公钥内容（如 `cat ~/.ssh/id_rsa.pub` 输出），回车后 Ctrl+D 结束输入。
  - 或长期挂载：在 `docker-compose.yml` 的 `picoclaw-gateway` 的 `volumes` 中取消注释  
    `- ./config/ssh/authorized_keys:/root/.ssh/authorized_keys:ro`，  
    在 NAS 项目下创建 `config/ssh/authorized_keys` 并写入本机公钥，重启容器。

**步骤二：从本机 SSH 登录**

- Gateway 在 **NAS** 上（如 NAS IP `192.168.3.23`）：在任意能访问 NAS 的机器上执行 `ssh -p 2222 root@192.168.3.23`，输入 `.env` 中的密码（或使用已配置的公钥）。
- Gateway 在 **本机**（与 `docker compose` 同机）：在该机执行 `ssh -p 2222 root@127.0.0.1`，输入 `.env` 中的密码（或公钥）。  
  若曾用 `--force-recreate` 重建过容器，需先执行 `ssh-keygen -f ~/.ssh/known_hosts -R '[127.0.0.1]:2222'` 再连，首次提示输入 `yes` 接受新主机密钥。

登录后容器内路径与 6.4 一致，工作区为 `/root/.picoclaw/workspace`，项目压缩包在 `/root/.picoclaw/workspace/projects/`。

**若密码正确仍 Permission denied**：多为修改 `.env` 后未重建容器，root 密码未更新。在项目目录执行 `docker compose --profile gateway up -d --force-recreate`，再试 SSH。若仍失败，可先手动设密码验证：`docker compose exec picoclaw-gateway sh -c 'echo "root:你的密码" | chpasswd'`，再 `ssh -p 2222 root@127.0.0.1`。

**若出现 “REMOTE HOST IDENTIFICATION HAS CHANGED”**：多为 `--force-recreate` 后容器重新生成了一组 SSH 主机密钥，本机 `~/.ssh/known_hosts` 里仍是旧密钥。删除旧条目后重连即可：`ssh-keygen -f ~/.ssh/known_hosts -R '[127.0.0.1]:2222'`（若 SSH 到 NAS 上的容器则把 `127.0.0.1` 换成 NAS IP），再执行 `ssh -p 2222 root@127.0.0.1`，提示时输入 `yes` 接受新密钥。

**若容器反复重启（出现 “Container is restarting” 无法 exec）**：先查看退出原因：`docker compose logs --tail=100 picoclaw-gateway`。若日志为 `exec /entrypoint-gateway.sh: no such file or directory`，多为入口脚本受 CRLF 或构建环境影响；当前 Dockerfile 已改为不依赖脚本文件，使用 `ENTRYPOINT ["/bin/sh", "-c", "内联逻辑", "sh"]` 直接执行启动 sshd + gateway，重建镜像即可。其他报错按日志内容排查。

---

## 7. 快速检查清单

在认为“部署完成”前，建议逐项确认：

- [ ] NAS 上 `go test ./...` 能正常通过。
- [ ] `make build` 能在 NAS 上成功生成 `build/picoclaw`。
- [ ] Docker 已安装，且 `docker compose --profile gateway build` 成功。
- [ ] `config/config.json` 中正确配置了至少一个 LLM Provider 的 `api_key`。
- [ ] 在飞书开放平台中创建了企业自建应用并启用机器人与 WebSocket 事件订阅。
- [ ] 飞书应用的 `app_id` / `app_secret` / `encrypt_key` / `verification_token` 已写入 `config/config.json`。
- [ ] `channels.feishu.enabled` 为 `true`，且 `allow_from` 中包含至少一个测试用户。
- [ ] `docker compose --profile gateway up -d` 运行后，日志中出现：
  - `Feishu channel enabled successfully`
  - `Feishu channel started (websocket mode)`
- [ ] 在飞书中向机器人发送消息，能收到 PicoClaw 的正常回复。

完成以上检查，即视为 **PicoClaw 在 NAS + 飞书内网聊天** 部署成功。

---

## 8. 飞书参数获取 - 用户端操作指南

本节面向**普通运维 / 管理员用户**，一步一步教你在飞书开放平台里拿到 PicoClaw 所需的 4 个关键参数，并填入 `config/config.json`：

- `app_id`（App ID）
- `app_secret`（App Secret）
- `encrypt_key`（加密密钥 Encrypt Key）
- `verification_token`（校验 Token）

### 8.1 在飞书开放平台创建企业自建应用

1. 使用企业管理员或有权限的账号登录：  
   打开浏览器访问 `https://open.feishu.cn`（国内版）或 `https://open.larksuite.com`（国际版）。
2. 左侧菜单进入 **「企业自建应用」**。
3. 点击 **「创建应用」**：
   - 选择 **企业自建应用** 类型。
   - 填写应用名称、应用描述、图标等信息。
4. 创建完成后，进入该应用的 **详情页**。

### 8.2 获取 App ID 与 App Secret

1. 在应用详情左侧菜单，找到 **「凭证与基础信息」**。
2. 在页面中可以看到：
   - **App ID**：复制这个值，稍后填入 `config.json` 里的 `app_id`。
   - **App Secret**：点击「查看」或「重置」按钮，复制密钥，稍后填入 `app_secret`。
3. 先把这两个值暂存到一个安全的地方（例如本地记事本），后面统一写入配置文件。

### 8.3 启用 WebSocket 事件订阅并获取 Encrypt Key / Verification Token

PicoClaw 通过 **WebSocket 事件订阅** 接收消息，不需要公网回调 URL。

1. 在应用详情左侧菜单，找到 **「事件订阅」**。
2. 在「事件订阅」页面中：
   - 将推送方式设置为：**WebSocket 模式 / 使用长连接接收事件**（不是 HTTP 回调 URL）。
3. 在同一页面的 **「加密策略」** 选项卡中，可以看到或设置：
   - **Encrypt Key（加密密钥）**：
     - 如果已经存在一条策略，直接复制这里显示的「加密密钥」字符串，稍后填入 `config.json` 的 `encrypt_key`。
     - 如果为空或未配置，可以在「加密策略」中新建策略，自行设置一个随机字符串（例如：`a8sd7f98a7sd8f9a7sd8f9`），保存后再复制这个值。
   - **Verification Token（校验 Token）**：
     - 一般由飞书自动生成，同样在「加密策略」区域中展示。
     - 直接复制这个值，稍后填入 `config.json` 的 `verification_token`。
4. 在事件列表中勾选需要的事件，至少包括：
   - `im.message.receive_v1`（接收消息事件，名称可能略有差异，以飞书实际为准）。
5. 点击 **保存 / 确认** 按钮，使配置生效。

### 8.4 给机器人开启权限

1. 在应用详情左侧菜单中找到 **「权限管理」**（有时在「安全与权限」下）。
2. 根据需要勾选与机器人消息权限相关的字段，例如（名称可能随版本变化，仅供参考）：
   - 读取用户发送给机器人的消息。
   - 以机器人身份发送消息。
3. 提交权限申请，必要时让企业管理员在飞书管理后台审批通过。

### 8.5 在 config/config.json 中填写 4 个参数

PicoClaw 项目中的 `config/config.json` 里，`feishu` 段示例为：

```jsonc
"feishu": {
  "enabled": true,
  "app_id": "YOUR_FEISHU_APP_ID",
  "app_secret": "YOUR_FEISHU_APP_SECRET",
  "encrypt_key": "YOUR_FEISHU_ENCRYPT_KEY",
  "verification_token": "YOUR_FEISHU_VERIFICATION_TOKEN",
  "allow_from": []
}
```

请按如下方式填写：

- 将「凭证与基础信息」页面中的 **App ID** 填入 `app_id`。
- 将 **App Secret** 填入 `app_secret`。
- 将事件订阅页面中的 **Encrypt Key** 填入 `encrypt_key`。
- 将事件订阅页面中的 **Verification Token** 填入 `verification_token`。
- `allow_from`：
  - 暂时可以先保持空数组 `[]`，表示不做额外白名单限制。
  - 以后如需仅允许特定用户，再填入对应的 user_id / open_id / union_id。

### 8.6 在 NAS 上重启 Gateway 让配置生效

完成以上 4 个参数的填写并保存 `config/config.json` 后，在本地终端执行：

```bash
ssh home_nas
cd /home/damncheater/Development/picoclaw

docker compose --profile gateway restart picoclaw-gateway
```

然后查看日志确认 Feishu 渠道已经启用：

```bash
docker compose logs --tail=100 picoclaw-gateway
```

如果看到类似日志：

- `Feishu channel enabled successfully`
- `Feishu channel started (websocket mode)`

说明机器人已经成功连上飞书云端。

### 8.7 在飞书客户端里测试聊天

1. 在飞书客户端中，找到刚刚创建的企业自建应用对应的 **机器人**：
   - 可以在「工作台」或「应用管理」里搜索应用名称。
2. 把机器人：
   - 拉进一个群聊，或者
   - 直接打开与机器人的单聊窗口。
3. 发送一条测试消息，例如：
   - `你好`
   - `2+2 等于几？`
4. 如果配置和 LLM API Key 都正常，几秒钟内应能看到机器人的回复。若无响应，可回到第 7 章的检查清单逐项排查。

