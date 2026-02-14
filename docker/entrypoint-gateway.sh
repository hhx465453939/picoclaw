#!/bin/sh
# Start sshd then run picoclaw gateway. Allows SSH login to container when ports 22 is mapped.
set -e
mkdir -p /var/run/sshd
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -A
fi
if [ -n "$ROOT_PASSWORD" ]; then
  echo "root:$ROOT_PASSWORD" | chpasswd
fi
# 后台启动 sshd，失败也不退出容器，保证 gateway 仍能运行
/usr/sbin/sshd || true
exec picoclaw "$@"
