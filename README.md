# Hermes One-Click 🚀

**一条命令在 Linux 服务器上装好并运行 Hermes Agent。**

Hermes Agent 是一个强大的 AI 智能助手，支持工具调用、代码执行、联网搜索、浏览器操控等能力。本项目让你在任何 Linux 服务器上，一行命令搞定部署。

## 前置条件

只需要一个 **Linux 服务器**（Ubuntu / Debian / CentOS）和 **curl**：

```bash
# 确认 curl 已安装
curl --version
```

> 不需要预装 Docker、Python 或 Node.js — 安装脚本会自动处理一切。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/q578tdd/hermes-one-click/main/install.sh | bash
```

> **安全提示**：建议先下载脚本审查内容，再执行：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/q578tdd/hermes-one-click/main/install.sh -o install.sh
> less install.sh    # 审查脚本
> bash install.sh    # 执行安装
> ```

安装过程中脚本会自动：
1. ✅ 检测操作系统（Ubuntu / Debian / CentOS）
2. ✅ 安装 Docker & Docker Compose（如果未安装）
3. ✅ 拉取 Hermes 镜像并构建
4. ✅ 启动 Redis（会话缓存）和 Hermes 主服务
5. ✅ 执行健康检查
6. ✅ 输出访问地址

## 验证服务

安装完成后，测试 Hermes 是否正常运行：

```bash
# 健康检查
curl http://localhost:8080/health

# 发起一次对话
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "你好，用一句话介绍 Hermes Agent"}]
  }'
```

如果返回 JSON 格式的回复，说明服务正常运行 ✅

## 配置

### 设置 API Key（必须）

编辑项目目录下的 `.env` 文件，填入你的 LLM API Key：

```bash
cd ~/hermes-one-click
vim .env
```

至少配置一个 Provider：

```ini
# DeepSeek（推荐，性价比高）
DEEPSEEK_API_KEY=sk-your-deepseek-api-key

# 或 OpenAI
OPENAI_API_KEY=sk-your-openai-api-key

# 或 Anthropic
ANTHROPIC_API_KEY=sk-ant-your-anthropic-api-key
```

配置完成后重启服务：

```bash
docker compose restart hermes
```

### 修改端口

默认端口 8080，如需修改：

```bash
# 方式 1：环境变量
export HERMES_PORT=9090
bash install.sh

# 方式 2：编辑 docker-compose.yml
vim ~/hermes-one-click/docker-compose.yml
# 修改 ${HERMES_PORT:-8080}:8080 为 9090:8080
docker compose up -d
```

## 服务管理

```bash
# 查看日志
cd ~/hermes-one-click && docker compose logs -f hermes

# 停止服务
cd ~/hermes-one-click && docker compose stop

# 启动服务
cd ~/hermes-one-click && docker compose start

# 重启服务（修改配置后）
cd ~/hermes-one-click && docker compose restart hermes

# 查看运行状态
cd ~/hermes-one-click && docker compose ps
```

## 卸载

```bash
cd ~/hermes-one-click

# 停止并删除容器
docker compose down -v

# 删除镜像
docker rmi hermes-agent:latest

# 删除项目文件
cd ~ && rm -rf ~/hermes-one-click

# 可选：卸载 Docker
# sudo apt-get remove docker-ce docker-ce-cli containerd.io
```

## 常见问题

### Q: 安装脚本报错 "Permission denied"

确保脚本有执行权限：
```bash
chmod +x install.sh
./install.sh
```

### Q: Docker 命令需要 sudo

脚本已尝试将当前用户加入 `docker` 组。重新登录后生效：
```bash
# 退出当前 SSH 会话后重连，或执行：
newgrp docker
```

### Q: 服务启动后访问不到

检查防火墙是否放行了端口：
```bash
# Ubuntu/Debian
sudo ufw allow 8080

# CentOS
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

### Q: 如何升级 Hermes？

```bash
cd ~/hermes-one-click
docker compose down
docker compose build hermes --no-cache
docker compose up -d
```

### Q: 容器日志报错 "API key not configured"

编辑 `~/hermes-one-click/.env`，填入正确的 API Key，然后：
```bash
docker compose restart hermes
```

## 项目结构

```
hermes-one-click/
├── install.sh           # 一键安装脚本（自动检测 OS、安装 Docker、启动服务）
├── docker-compose.yml   # Docker Compose 编排（Hermes + Redis）
├── Dockerfile           # Hermes Docker 镜像构建
├── .env.example         # 环境变量模板（复制为 .env 使用）
├── .gitignore           # Git 忽略规则
└── README.md            # 本文件
```

## 技术栈

| 组件 | 用途 |
|------|------|
| [Hermes Agent](https://github.com/nousresearch/hermes-agent) | AI 智能助手核心 |
| Redis 7 | 会话缓存与状态管理 |
| Docker / Docker Compose | 容器化部署与编排 |

## License

MIT
