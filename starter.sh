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

# 检查拉取到的内容是否包含合法的 ssh key 特征 (ssh-rsa, ssh-ed25519 等)
if echo "$PUB_KEYS" | grep -qE "^ssh-|^ecdsa-"; then
    echo "Successfully retrieved public key(s) for ${GITHUB_USER}."
    
    # 为当前系统用户(node)创建并配置 .ssh 目录
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$PUB_KEYS" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    # 创建 SSH 运行所需的特权分离目录
    sudo mkdir -p /run/sshd
    sudo chmod 755 /run/sshd

    # 确保生成了主机密钥（通常在安装openssh时已生成，保险起见再执行一次）
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
if [ -n "$CLOUDFLARED_TOKEN" ]; then
    echo "CLOUDFLARED_TOKEN detected. Starting cloudflared..."
    # 同样使用 pm2 后台挂载 cloudflared 进程
    npx --yes pm2 start "cloudflared tunnel --no-autoupdate run --token ${CLOUDFLARED_TOKEN}" --name cloudflared
else
    echo "Warning: CLOUDFLARED_TOKEN is not set. Skipping cloudflared startup."
fi


# =========================================================
# 3. 启动主应用 (CMD)
# =========================================================
echo "Starting main application..."

# 使用 exec 可以让 Node.js 进程替换当前的 Bash 脚本进程 (PID 1)，
# 这样容器能正确接收并处理 SIGTERM 等系统级停止信号。
exec node openclaw.mjs gateway --allow-unconfigured
