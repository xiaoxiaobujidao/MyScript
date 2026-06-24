#!/bin/bash

# 安装 XanMod 内核并开启 BBRv3 的脚本
# 参考: https://xanmod.org/
# 适用于 Debian/Ubuntu 系统

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SYSCTL_BBR_CONF="/etc/sysctl.d/99-bbr.conf"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
        echo "使用: sudo $0"
        exit 1
    fi
}

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

    if ! command -v lsb_release >/dev/null 2>&1; then
        echo -e "${RED}错误: 未找到 lsb_release，请先安装 lsb-release${NC}"
        exit 1
    fi

    CODENAME=$(lsb_release -sc)
    echo -e "${GREEN}发行版代号: $CODENAME${NC}"
}

check_arch() {
    ARCH=$(dpkg --print-architecture)
    echo -e "${GREEN}系统架构: $ARCH${NC}"

    if [[ "$ARCH" != "amd64" ]]; then
        echo -e "${RED}错误: XanMod 仅支持 amd64 架构${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${GREEN}正在更新软件包列表...${NC}"
    apt-get update -qq

    echo -e "${GREEN}正在安装必要的依赖...${NC}"

    PACKAGES="curl wget gnupg apt-transport-https ca-certificates lsb-release"

    if [[ "$ID" == "ubuntu" ]]; then
        PACKAGES="$PACKAGES software-properties-common"
    fi

    apt-get install -y -qq $PACKAGES
}

add_xanmod_repo() {
    echo -e "${GREEN}正在添加 XanMod 内核仓库...${NC}"

    mkdir -p /etc/apt/keyrings
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" \
        | tee /etc/apt/sources.list.d/xanmod-release.list

    apt-get update -qq

    echo -e "${GREEN}XanMod 仓库添加成功${NC}"
}

detect_kernel_package() {
    local psabi_script="/tmp/check_x86-64_psabi.sh"
    local psabi_output

    echo -e "${GREEN}正在检测 CPU 架构级别...${NC}" >&2

    curl -fsSL -o "$psabi_script" https://dl.xanmod.org/check_x86-64_psabi.sh
    chmod +x "$psabi_script"
    psabi_output=$("$psabi_script" 2>&1 || true)
    echo "$psabi_output" >&2

    if echo "$psabi_output" | grep -qE "x86-64-v[34]"; then
        echo "linux-xanmod-x64v3"
    elif echo "$psabi_output" | grep -q "x86-64-v2"; then
        echo "linux-xanmod-x64v2"
    elif echo "$psabi_output" | grep -qE "x86-64-v1|x86-64[^-]"; then
        echo "linux-xanmod-lts-x64v1"
    else
        echo -e "${YELLOW}无法识别 CPU 级别，默认使用 linux-xanmod-x64v3${NC}" >&2
        echo "linux-xanmod-x64v3"
    fi
}

install_xanmod_kernel() {
    local kernel_pkg
    kernel_pkg=$(detect_kernel_package)

    echo -e "${GREEN}正在安装 XanMod 内核: ${kernel_pkg}${NC}"

    echo -e "${YELLOW}可用的 XanMod 内核版本:${NC}"
    apt-cache search linux-xanmod | grep "^linux-xanmod" | head -8

    apt-get install -y "$kernel_pkg"

    echo -e "${GREEN}XanMod 内核安装成功${NC}"
}

configure_bbr() {
    echo -e "${GREEN}正在配置 BBRv3...${NC}"
    echo -e "${YELLOW}说明: XanMod 内核内置 BBRv3 (tcp_bbr 模块)，sysctl 使用 bbr${NC}"

    cat > "$SYSCTL_BBR_CONF" << 'EOF'
# BBRv3 (XanMod 内核内置 tcp_bbr)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_slow_start_after_idle=0
EOF

    sysctl -p "$SYSCTL_BBR_CONF" 2>/dev/null || {
        echo -e "${YELLOW}当前内核尚未切换，BBR 配置将在重启后生效${NC}"
    }

    echo -e "${GREEN}BBRv3 配置完成${NC}"
}

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

main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  XanMod 内核 + BBRv3 安装脚本${NC}"
    echo -e "${GREEN}  参考: https://xanmod.org/${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo

    check_root
    check_system
    check_arch
    install_dependencies
    add_xanmod_repo
    install_xanmod_kernel
    configure_bbr
    verify_config

    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${YELLOW}请重启系统以使新内核和 BBRv3 生效:${NC}"
    echo -e "${YELLOW}  sudo reboot${NC}"
    echo -e "${GREEN}========================================${NC}"
}

main
