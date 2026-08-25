#!/bin/bash

# 强制删除所有名称以 ddns_ 开头的 Docker 容器
# 用法: ./rm_ddns.sh
# 在线: curl -s https://raw.githubusercontent.com/xiaoxiaobujidao/MyScript/main/docker/rm_ddns.sh | bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}错误: 未找到 docker 命令${NC}"
    exit 1
fi

# docker --filter name= 是模糊匹配，这里用精确前缀匹配
containers=$(docker ps -a --format '{{.Names}}' | grep '^ddns_' || true)

if [ -z "$containers" ]; then
    echo -e "${YELLOW}没有找到名称以 ddns_ 开头的容器${NC}"
    exit 0
fi

echo -e "${YELLOW}即将强制删除以下容器:${NC}"
echo "$containers"
echo ""

# 容器名通常不含空格，按行传给 docker rm -f
echo "$containers" | xargs docker rm -f

echo ""
echo -e "${GREEN}已删除全部 ddns_ 开头的容器${NC}"
