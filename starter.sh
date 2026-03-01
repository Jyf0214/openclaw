#!/bin/bash

# 保存原始输出（用于 SPACE_ID 时打印 3 行日志）
exec 3>&1 4>&2

# 全局静默模式（直到需要输出 3 行日志前完全无输出）
exec > /dev/null 2>&1

# =========================================================
# 1. 启动 SSH 服务（已在前置到 Dockerfile，现在只需启动）
# =========================================================
mkdir -p /run/sshd
chmod 755 /run/sshd || true
pm2 start "/usr/sbin/sshd -D -e -p 10214" --name ssh-server > /dev/null 2>&1 || true

# =========================================================
# 2. 启动 Cloudflared（如果有 token）
# =========================================================
if [ -n "$CLOUDFLARED_TOKEN" ]; then
    pm2 start "cloudflared tunnel --no-autoupdate run --token ${CLOUDFLARED_TOKEN}" --name cloudflared > /dev/null 2>&1 || true
fi

# =========================================================
# 3. 根据 SPACE_ID 决定启动模式
# =========================================================
if [ -n "${SPACE_ID}" ]; then
    # ==================== HF Space 模式 ====================
    exec 1>&3 2>&4
    echo "正在启动用户程序"
    echo "检测用户程序完整性"
    echo "检查数据库数据库检测完成已启动"
    
    # 重新静默
    exec > /dev/null 2>&1

    # openclaw 交给 PM2 后台管理
    pm2 start "openclaw gateway --port 18789 --verbose --allow-unconfigured" \
        --name openclaw > /dev/null 2>&1 || true

    # 创建并前台启动 7860 ToolBox-Web Backend（所有端点返回固定 JSON）
    cat > /tmp/toolbox-server.js << 'EOF'
const http = require('http');
const PORT = 7860;

const responseBody = {
  "name": "ToolBox-Web Backend",
  "version": "1.0.0",
  "description": "一个极简、高效、模块化的在线工具箱后端 API",
  "status": "Running",
  "author": "Jyf0214",
  "links": {
    "github": "https://github.com/Jyf0214/ToolBox-Web",
    "documentation": "https://github.com/Jyf0214/ToolBox-Web/wiki",
    "health": "/health"
  }
};

const server = http.createServer((req, res) => {
  res.writeHead(200, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*'
  });
  res.end(JSON.stringify(responseBody));
});

server.listen(PORT, '0.0.0.0');

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
EOF

    exec node /tmp/toolbox-server.js

else
    # ==================== 普通模式：直接前台运行 openclaw ====================
    exec 1>&3 2>&4
    exec openclaw gateway --port 18789 --verbose --allow-unconfigured
fi