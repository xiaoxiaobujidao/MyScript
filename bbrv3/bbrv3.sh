#!/bin/bash

# 安装 XanMod 内核并开启 BBR3 的脚本
# 适用于 Debian/Ubuntu 系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
        echo "使用: sudo $0"
        exit 1
    fi
}

# 检查系统类型
check_system() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}错误: 无法检测系统类型${NC}"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        echo -e "${RED}错误: 此脚本仅支持 Debian/Ubuntu 系统${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}检测到系统: $PRETTY_NAME${NC}"
}

# 检查架构
check_arch() {
    ARCH=$(dpkg --print-architecture)
    echo -e "${GREEN}系统架构: $ARCH${NC}"
    
    if [[ "$ARCH" != "amd64" ]]; then
        echo -e "${YELLOW}警告: XanMod 主要支持 amd64 架构${NC}"
        read -p "是否继续? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 安装必要的依赖
install_dependencies() {
    echo -e "${GREEN}正在更新软件包列表...${NC}"
    apt-get update -qq
    
    # 检测系统类型
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}错误: 无法检测系统类型${NC}"
        exit 1
    fi
    . /etc/os-release
    
    echo -e "${GREEN}正在安装必要的依赖...${NC}"
    
    # 基础依赖包
    PACKAGES="curl wget gnupg2 apt-transport-https ca-certificates"
    
    # software-properties-common 仅在 Ubuntu 上可用
    if [[ "$ID" == "ubuntu" ]]; then
        PACKAGES="$PACKAGES software-properties-common"
    fi
    
    apt-get install -y -qq $PACKAGES
}

# 添加 XanMod 内核仓库
add_xanmod_repo() {
    echo -e "${GREEN}正在添加 XanMod 内核仓库...${NC}"
    
    # 添加 GPG 密钥
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    
    # 添加仓库
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
    
    # 更新软件包列表
    apt-get update -qq
    
    echo -e "${GREEN}XanMod 仓库添加成功${NC}"
}

# 安装 XanMod 内核
install_xanmod_kernel() {
    echo -e "${GREEN}正在安装 XanMod 内核...${NC}"
    
    # 列出可用的 XanMod 内核版本
    echo -e "${YELLOW}可用的 XanMod 内核版本:${NC}"
    apt-cache search linux-xanmod | grep "^linux-xanmod" | head -5
    
    # 安装最新的稳定版本
    apt-get install -y linux-xanmod-x64v3 || {
        echo -e "${YELLOW}尝试安装通用版本...${NC}"
        apt-get install -y linux-xanmod
    }
    
    echo -e "${GREEN}XanMod 内核安装成功${NC}"
}

# 验证配置
verify_config() {
    echo -e "${GREEN}正在验证配置...${NC}"
    
    echo -e "${YELLOW}当前内核版本:${NC}"
    uname -r
    
    echo -e "${YELLOW}可用的拥塞控制算法:${NC}"
    cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "需要重启后查看"
    
    echo -e "${YELLOW}当前使用的拥塞控制算法:${NC}"
    cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "需要重启后查看"
    
    echo -e "${YELLOW}当前队列规则:${NC}"
    cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "需要重启后查看"
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  XanMod 内核 + BBR3 安装脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    
    check_root
    check_system
    check_arch
    install_dependencies
    add_xanmod_repo
    install_xanmod_kernel
    verify_config
    
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${YELLOW}请重启系统以使新内核和 BBR3 生效:${NC}"
    echo -e "${YELLOW}  sudo reboot${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 运行主函数
main
