#!/bin/bash

# 保存原始 stdout 和 stderr
exec 3>&1 4>&2

# 进入完全静默模式（直到 openclaw 启动前不输出任何日志，即使出错）
exec > /dev/null 2>&1

# =========================================================
# 1. 获取 GitHub 公钥并配置 SSH
# =========================================================
GITHUB_USER="Jyf0214"

PUB_KEYS=$(curl -fsSL "https://github.com/${GITHUB_USER}.keys" || echo "")

if echo "$PUB_KEYS" | grep -qE "^ssh-|^ecdsa-"; then
    TARGET_USER="node"
    TARGET_HOME="/home/node"

    sudo chmod 755 ${TARGET_HOME} || true
    sudo mkdir -p ${TARGET_HOME}/.ssh
    sudo chmod 700 ${TARGET_HOME}/.ssh
    sudo bash -c "echo '$PUB_KEYS' > ${TARGET_HOME}/.ssh/authorized_keys"
    sudo chmod 600 ${TARGET_HOME}/.ssh/authorized_keys
    sudo chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/.ssh

    sudo mkdir -p /run/sshd
    sudo chmod 755 /run/sshd
    sudo ssh-keygen -A

    npx --yes pm2 start "sudo /usr/sbin/sshd -D -e -p 10214" --name ssh-server
fi

# =========================================================
# 2. 启动 Cloudflared (如果环境变量存在)
# =========================================================
if [ -n "$CLOUDFLARED_TOKEN" ]; then
    npx --yes pm2 start "cloudflared tunnel --no-autoupdate run --token ${CLOUDFLARED_TOKEN}" --name cloudflared
fi

# =========================================================
# 3. 权限处理
# =========================================================
sudo chmod -R 777 /home/node/.openclaw || true

# 恢复正常输出
exec 1>&3 2>&4

# 移交主进程给 openclaw（此时开始正常输出日志）
exec openclaw gateway --port 18789 --verbose --allow-unconfigured