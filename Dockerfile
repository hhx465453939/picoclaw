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

# Gateway 入口：先启动 sshd，再 exec picoclaw（agent 服务在 compose 中覆盖 entrypoint）
COPY docker/entrypoint-gateway.sh /entrypoint-gateway.sh
RUN chmod +x /entrypoint-gateway.sh

ENTRYPOINT ["/entrypoint-gateway.sh"]
CMD ["gateway"]
