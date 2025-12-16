#!/bin/bash
# BBRv3 安装脚本 - 通过 XanMod 内核启用 BBRv3
# 警告：此脚本会安装新内核并重启系统

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 检查系统类型
check_system() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "此脚本仅支持 Debian/Ubuntu 系统"
        exit 1
    fi
    
    if [[ $(uname -m) != "x86_64" ]]; then
        log_error "此脚本仅支持 x86_64 架构"
        exit 1
    fi
}

# 检查是否已安装 XanMod 内核
check_xanmod_installed() {
    if dpkg -l | grep -q "linux-xanmod"; then
        log_warn "检测到已安装 XanMod 内核"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消安装"
            exit 0
        fi
    fi
}

# 获取 CPU 微架构版本
get_cpu_version() {
    log_info "正在检测 CPU 微架构版本..."
    
    # 下载并执行检测脚本
    local check_script=$(mktemp)
    if ! curl -sSL https://dl.xanmod.org/check_x86-64_psabi.sh -o "$check_script"; then
        log_error "无法下载 CPU 检测脚本"
        rm -f "$check_script"
        exit 1
    fi
    
    chmod +x "$check_script"
    local version=$("$check_script" 2>/dev/null | tail -n 1)
    rm -f "$check_script"
    
    if [[ -z "$version" ]]; then
        log_warn "无法自动检测 CPU 版本，使用 v3（通用版本）"
        version="3"
    else
        # 提取版本号（最后一个字符）
        version="${version: -1}"
        log_info "检测到 CPU 版本: v$version"
    fi
    
    echo "$version"
}

# 安装依赖
install_dependencies() {
    log_info "正在更新软件包列表..."
    if ! apt update; then
        log_error "软件包列表更新失败"
        exit 1
    fi
    
    log_info "正在安装依赖包..."
    if ! apt install -y gnupg curl mawk; then
        log_error "依赖包安装失败"
        exit 1
    fi
}

# 添加 XanMod 仓库
add_xanmod_repo() {
    log_info "正在添加 XanMod 仓库..."
    
    # 下载并导入 GPG 密钥
    if ! curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg; then
        log_error "GPG 密钥导入失败"
        exit 1
    fi
    
    # 添加仓库源
    if [[ ! -f /etc/apt/sources.list.d/xanmod-release.list ]]; then
        echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | \
            tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null
        log_info "XanMod 仓库已添加"
    else
        log_warn "XanMod 仓库已存在，跳过添加"
    fi
}

# 安装 XanMod 内核
install_xanmod_kernel() {
    local version=$1
    log_info "正在更新软件包列表..."
    if ! apt update; then
        log_error "软件包列表更新失败"
        exit 1
    fi
    
    log_info "正在安装 linux-xanmod-x64v$version..."
    if ! apt install -y "linux-xanmod-x64v$version"; then
        log_error "XanMod 内核安装失败"
        exit 1
    fi
    
    log_info "XanMod 内核安装成功"
}

# 配置 BBRv3
configure_bbrv3() {
    log_info "正在配置 BBRv3..."
    
    # 创建 BBRv3 配置文件
    local bbr_config="/etc/sysctl.d/99-bbrv3.conf"
    
    # 检查是否已存在配置
    if [[ -f "$bbr_config" ]]; then
        log_warn "BBRv3 配置文件已存在，将覆盖"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消配置"
            return
        fi
    fi
    
    # 写入 BBRv3 配置
    cat > "$bbr_config" <<'EOF'
# BBRv3 配置
# 使用 fq_pie 队列调度器（BBRv3 推荐）
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲区优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# MTU 探测
net.ipv4.tcp_mtu_probing=1
EOF
    
    log_info "BBRv3 配置已写入 $bbr_config"
    
    # 应用配置（无需重启即可生效部分设置）
    log_info "正在应用 BBRv3 配置..."
    sysctl -p "$bbr_config" > /dev/null 2>&1 || true
}

# 主函数
main() {
    log_info "开始安装 BBRv3（通过 XanMod 内核）"
    log_warn "此脚本将安装新内核并需要重启系统"
    
    check_root
    check_system
    check_xanmod_installed
    
    install_dependencies
    add_xanmod_repo
    
    local cpu_version=$(get_cpu_version)
    install_xanmod_kernel "$cpu_version"
    
    configure_bbrv3
    
    log_info "安装完成！"
    log_warn "系统需要重启以使用新内核和 BBRv3"
    echo
    read -p "是否立即重启？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "系统将在 5 秒后重启..."
        sleep 5
        reboot
    else
        log_info "请稍后手动重启系统以应用更改"
        log_info "重启后，可以使用以下命令验证 BBRv3："
        log_info "  sysctl net.ipv4.tcp_congestion_control"
        log_info "  sysctl net.core.default_qdisc"
    fi
}

# 执行主函数
main "$@"
