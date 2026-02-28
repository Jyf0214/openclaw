#!/bin/bash

# 打印初始信息
echo "=== Starting container initialization ==="

# =========================================================
# 1. 获取 GitHub 公钥并配置 SSH
# =========================================================
GITHUB_USER="Jyf0214"
echo "Fetching public keys for GitHub user: ${GITHUB_USER}..."

# 拉取公钥内容
PUB_KEYS=$(curl -fsSL "https://github.com/${GITHUB_USER}.keys" || echo "")

# 检查拉取到的内容是否包含合法的 ssh key 特征
if echo "$PUB_KEYS" | grep -qE "^ssh-|^ecdsa-"; then
    echo "Successfully retrieved public key(s) for ${GITHUB_USER}."

    # 【核心修复区】：无论谁运行此脚本，都强制将密钥配置给 node 用户
    TARGET_USER="node"
    TARGET_HOME="/home/node"

    # 1. 防止 SSH 严格模式 (StrictModes) 因为父目录权限过宽而拒绝认证
    sudo chmod 755 ${TARGET_HOME} || true

    # 2. 创建目录并写入密钥
    sudo mkdir -p ${TARGET_HOME}/.ssh
    sudo chmod 700 ${TARGET_HOME}/.ssh
    # 注意：这里需要借用 bash -c 以 sudo 权限写入文件
    sudo bash -c "echo '$PUB_KEYS' > ${TARGET_HOME}/.ssh/authorized_keys"
    sudo chmod 600 ${TARGET_HOME}/.ssh/authorized_keys

    # 3. 修正所有权 (非常重要！确保 node 用户拥有这些文件)
    sudo chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/.ssh

    # 创建 SSH 运行所需的特权分离目录
    sudo mkdir -p /run/sshd
    sudo chmod 755 /run/sshd

    # 确保生成了主机密钥
    sudo ssh-keygen -A

    # 使用 PM2 启动 SSH 服务 (-D 阻止后台运行交由pm2管理，-p 指定端口)
    echo "Starting SSH server on port 10214 via PM2..."
    npx --yes pm2 start "sudo /usr/sbin/sshd -D -e -p 10214" --name ssh-server
else
    echo "Warning: Failed to fetch valid public keys. SSH server will NOT be started."
fi

# =========================================================
# 2. 启动 Cloudflared (如果环境变量存在)
# =========================================================
if[ -n "$CLOUDFLARED_TOKEN" ]; then
    echo "CLOUDFLARED_TOKEN detected. Starting cloudflared..."
    npx --yes pm2 start "cloudflared tunnel --no-autoupdate run --token ${CLOUDFLARED_TOKEN}" --name cloudflared
else
    echo "Warning: CLOUDFLARED_TOKEN is not set. Skipping cloudflared startup."
fi

# =========================================================
# 3. 启动主应用 (CMD)
# =========================================================
echo "Starting main application..."
sudo chmod -R 777 /home/node/.openclaw || true

# 移交主进程给 openclaw
exec openclaw gateway --port 18789 --verbose --allow-unconfigured