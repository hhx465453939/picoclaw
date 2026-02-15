## ============================================================
## Stage 1: Build the picoclaw binary
## ============================================================
FROM golang:1.25-alpine AS builder

# Use a Go module proxy to improve reliability in restricted networks
ENV GOPROXY=https://goproxy.cn,direct

RUN apk add --no-cache git make

WORKDIR /src

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN make build

# ============================================================
# Stage 2: Minimal runtime image
# ============================================================
FROM alpine:3.21

# 基础与 SSH：client 用于容器内连出；server 用于从本机 SSH 登录到容器
RUN apk add --no-cache ca-certificates tzdata openssh-client openssh-server

# 默认使用北京时间（Agent 的 Current Time、Cron、Heartbeat 等均依赖此时区）
ENV TZ=Asia/Shanghai

# Copy binary
COPY --from=builder /src/build/picoclaw /usr/local/bin/picoclaw

# Copy builtin skills
COPY --from=builder /src/skills /opt/picoclaw/skills

# Create picoclaw home directory
RUN mkdir -p /root/.picoclaw/workspace/skills && \
    cp -r /opt/picoclaw/skills/* /root/.picoclaw/workspace/skills/ 2>/dev/null || true

# SSH 登录到容器：允许 root 登录（密码或密钥由 entrypoint/compose 配置）
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

# Gateway 入口：直接用 /bin/sh -c 内联逻辑，不依赖脚本文件。运行时 argv 为 [sh, gateway]，故 $@=gateway，不要 shift
ENTRYPOINT ["/bin/sh", "-c", "set -e; mkdir -p /var/run/sshd; [ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -A; [ -z \"$ROOT_PASSWORD\" ] || echo \"root:$ROOT_PASSWORD\" | chpasswd; /usr/sbin/sshd || true; exec picoclaw \"$@\"", "sh"]
CMD ["gateway"]
