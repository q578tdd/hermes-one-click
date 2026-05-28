#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hermes One-Click Installer
# 一条命令安装并运行 Hermes Agent
# 用法: curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
# ============================================================

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1"; exit 1; }
info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }

# ---------- 安全检查 ----------
# 拒绝 root 直接运行（建议用普通用户 + docker group）
if [ "$(id -u)" = "0" ]; then
    warn "不建议用 root 运行。推荐使用有 docker 权限的普通用户。"
    warn "继续运行需谨慎。按 Ctrl+C 取消，按 Enter 继续..."
    read -r
fi

# ---------- 检测 OS ----------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif command -v lsb_release &>/dev/null; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    else
        OS="unknown"
    fi
    echo "$OS"
}

OS=$(detect_os)
info "检测到操作系统: ${OS}"

case "$OS" in
    ubuntu|debian)
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
        DOCKER_COMPOSE_PKG="docker-compose-plugin"
        ;;
    centos|rhel|fedora)
        PKG_MANAGER="yum"
        PKG_UPDATE="yum check-update -q || true"
        PKG_INSTALL="yum install -y -q"
        DOCKER_COMPOSE_PKG="docker-compose-plugin"
        ;;
    *)
        err "不支持的操作系统: $OS。仅支持 Ubuntu/Debian/CentOS/RHEL。"
        ;;
esac

# ---------- 检查并安装 Docker ----------
install_docker() {
    if command -v docker &>/dev/null; then
        log "Docker 已安装 ($(docker --version))"
        # 检查 docker 守护进程是否运行
        if ! docker info &>/dev/null; then
            warn "Docker 守护进程未运行，尝试启动..."
            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
            sleep 2
            if ! docker info &>/dev/null; then
                err "无法启动 Docker 守护进程。请手动检查。"
            fi
        fi
        return 0
    fi

    info "正在安装 Docker..."
    case "$OS" in
        ubuntu|debian)
            sudo $PKG_UPDATE
            sudo $PKG_INSTALL curl ca-certificates
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo curl -fsSL https://download.docker.com/linux/${OS}/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo $PKG_UPDATE
            sudo $PKG_INSTALL docker-ce docker-ce-cli containerd.io ${DOCKER_COMPOSE_PKG}
            ;;
        centos|rhel|fedora)
            sudo $PKG_UPDATE
            sudo $PKG_INSTALL yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-compose-plugin
            sudo systemctl enable docker
            sudo systemctl start docker
            ;;
    esac

    # 将当前用户加入 docker 组（避免每次 sudo）
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        warn "已将 $USER 加入 docker 组。可能需要重新登录才能生效。"
    fi

    log "Docker 安装完成"
}

install_docker

# ---------- 检查 docker compose ----------
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
    log "Docker Compose 可用 ($(docker compose version))"
elif docker-compose --version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    log "Docker Compose 可用 ($(docker-compose --version))"
else
    err "Docker Compose 不可用。请手动安装。"
fi

# ---------- 创建项目目录 ----------
PROJECT_DIR="$HOME/hermes-one-click"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
log "项目目录: $PROJECT_DIR"

# ---------- 生成 docker-compose.yml ----------
info "生成 docker-compose.yml..."
cat > docker-compose.yml << 'DOCKER_COMPOSE_EOF'
services:
  redis:
    image: redis:7-alpine
    container_name: hermes-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  hermes:
    build:
      context: .
      dockerfile: Dockerfile
    image: hermes-agent:latest
    container_name: hermes-agent
    restart: unless-stopped
    ports:
      - "${HERMES_PORT:-8080}:8080"
    depends_on:
      redis:
        condition: service_healthy
    volumes:
      - hermes_config:/root/.hermes
      - hermes_data:/root/.hermes_data
    environment:
      - HERMES_CONFIG_DIR=/root/.hermes
      - REDIS_URL=redis://redis:6379/0
      - TZ=${TZ:-UTC}
    env_file:
      - .env

volumes:
  redis_data:
  hermes_config:
  hermes_data:
DOCKER_COMPOSE_EOF
log "docker-compose.yml 已生成"

# ---------- 生成 Dockerfile ----------
info "生成 Dockerfile..."
cat > Dockerfile << 'DOCKERFILE_EOF'
# ============================================================
# Hermes Agent Docker Image
# 基于 Python 3.12-slim，安装 hermes-agent + 浏览器依赖
# ============================================================
FROM python:3.12-slim

LABEL org.opencontainers.image.title="Hermes Agent"
LABEL org.opencontainers.image.description="AI assistant with tool-calling capabilities"
LABEL org.opencontainers.image.version="0.13.0"

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 安装 Hermes Agent
RUN pip install --no-cache-dir hermes-agent

# 创建工作目录
WORKDIR /workspace

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 默认启动命令
CMD ["hermes", "web", "--host", "0.0.0.0", "--port", "8080"]
DOCKERFILE_EOF
log "Dockerfile 已生成"

# ---------- 生成 .env.example ----------
info "生成 .env.example..."
cat > .env.example << 'ENVEOF'
# ============================================================
# Hermes Agent 环境变量配置
# 复制此文件为 .env 并填写你的 API Key
# ============================================================
# cp .env.example .env && vim .env

# ---------- LLM Provider (必填，至少一个) ----------
# DeepSeek
DEEPSEEK_API_KEY=sk-your-deepseek-api-key
# OpenAI
OPENAI_API_KEY=sk-your-openai-api-key
# Anthropic
ANTHROPIC_API_KEY=sk-ant-your-anthropic-api-key

# ---------- Hermes 配置 ----------
# Web 服务端口（默认 8080）
HERMES_PORT=8080
# 默认模型
HERMES_DEFAULT_MODEL=deepseek-v4-flash
# LLM Provider
HERMES_PROVIDER=deepseek

# ---------- 时区 ----------
TZ=Asia/Shanghai

# ---------- 消息通道（可选） ----------
# Telegram Bot Token
# TELEGRAM_BOT_TOKEN=your-telegram-bot-token
# Discord Bot Token
# DISCORD_BOT_TOKEN=your-discord-bot-token
ENVEOF
log ".env.example 已生成"

# ---------- 初始化 .env（如果不存在） ----------
if [ ! -f .env ]; then
    cp .env.example .env
    warn ".env 已从 .env.example 创建，请编辑 .env 填入你的 API Key"
else
    log ".env 已存在，跳过"
fi

# ---------- 生成 .gitignore ----------
info "生成 .gitignore..."
cat > .gitignore << 'GITIGNORE_EOF'
# ============================================================
# Hermes One-Click — .gitignore
# ============================================================

# 环境变量（含 API Key）
.env

# Python
__pycache__/
*.py[cod]
*.egg-info/
dist/
build/

# Docker
.docker/

# 系统文件
.DS_Store
Thumbs.db
*.swp
*.swo

# IDE
.idea/
.vscode/
*.iml

# Logs
*.log

# 临时文件
/tmp/
GITIGNORE_EOF
log ".gitignore 已生成"

# ---------- 构建 Docker 镜像 ----------
info "正在构建 Hermes Docker 镜像（首次可能需要 3-5 分钟）..."
$COMPOSE_CMD build hermes 2>&1 | tail -5
log "Docker 镜像构建完成"

# ---------- 启动服务 ----------
info "正在启动服务..."
$COMPOSE_CMD up -d 2>&1
log "服务已启动"

# ---------- 健康检查 ----------
info "执行健康检查..."
sleep 5
HERMES_PORT=${HERMES_PORT:-8080}
MAX_RETRIES=12
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf "http://localhost:${HERMES_PORT}/health" > /dev/null 2>&1; then
        log "Hermes Agent 健康检查通过"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        warn "健康检查超时，但服务可能仍在启动中..."
        warn "请稍后手动执行: curl http://localhost:${HERMES_PORT}/health"
    else
        sleep 5
    fi
done

# ---------- 输出访问信息 ----------
echo ""
echo "============================================"
echo -e " ${GREEN}${BOLD}Hermes Agent 安装完成！${NC}"
echo "============================================"
echo ""
echo -e "  ${BOLD}访问地址:${NC}  http://localhost:${HERMES_PORT}"
echo -e "  ${BOLD}项目目录:${NC}  ${PROJECT_DIR}"
echo ""
echo -e "  ${BOLD}常用命令:${NC}"
echo "    docker compose logs -f hermes    # 查看日志"
echo "    docker compose stop              # 停止服务"
echo "    docker compose start             # 启动服务"
echo "    docker compose down -v           # 停止并删除数据"
echo ""
echo -e "  ${YELLOW}${BOLD}第一次使用？${NC}"
echo "  1. 编辑 .env 填入 API Key:"
echo "     vim ${PROJECT_DIR}/.env"
echo "  2. 重启服务:"
echo "     cd ${PROJECT_DIR} && docker compose restart hermes"
echo ""
echo -e "  ${BOLD}测试服务:${NC}"
echo "     curl http://localhost:${HERMES_PORT}/v1/chat/completions \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d '{\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}'"
echo ""
echo "============================================"
