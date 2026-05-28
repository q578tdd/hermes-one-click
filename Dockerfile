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

# 安装 Hermes Agent（官方 PyPI 包）
RUN pip install --no-cache-dir hermes-agent

# 创建工作目录
WORKDIR /workspace

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 暴露端口
EXPOSE 8080

# 默认启动命令
# 用户可通过 docker-compose.yml 中的 command 覆盖
CMD ["hermes", "web", "--host", "0.0.0.0", "--port", "8080"]
