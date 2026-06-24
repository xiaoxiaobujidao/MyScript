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

install_xanmod_gpg_key() {
    local tmp_key="/tmp/xanmod-archive.key"
    local keyring="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
    local url

    import_gpg_key() {
        rm -f "$keyring"
        gpg --batch --yes --dearmor -o "$keyring" < "$1"
        [ -s "$keyring" ]
    }

    for url in \
        "https://dl.xanmod.org/archive.key" \
        "https://gitlab.com/afrd.gpg"; do
        if curl -fsSL -o "$tmp_key" "$url" && grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$tmp_key"; then
            if import_gpg_key "$tmp_key"; then
                rm -f "$tmp_key"
                echo -e "${GREEN}GPG 密钥下载成功${NC}"
                return 0
            fi
        fi
        rm -f "$tmp_key"
        echo -e "${YELLOW}无法从 ${url} 获取有效 GPG 密钥，尝试备用源...${NC}"
    done

    cat > "$tmp_key" <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2

mQENBFhxW04BCAC61HuxBVf1XJiQjXu/DSAtVcnuK38geDoDjcqFtHskFy32NgJG
X118EFNym6noF+oibaSftI9yjHthWvMnYZ/+DPwd7YZhbAjBvxMIQCsP6cFVxrgc
VV8g+uh4TCfbpalDBFoncRhQCgkmDN9Vd4kIWRh6BHJuzpKB/h2KxUHZVEKgWlK2
dR1xUtbrc+kp8gLwPbxTgC3tZ4x2uMMMlnbyCMSRa5oJ/AvoW4W1XphKL9ivsFHM
PSQkUBDvgv2RPw+0XBxPy8SYE0r0onx0ZIpjJRTODt3bSV6/0owwlpNogV9bT8HY
kl3+w3mTwax6S1akHZuJtLkZS0uUBz1BHt5bABEBAAG0IVhhbk1vZCBLZXJuZWwg
PGtlcm5lbEB4YW5tb2Qub3JnPokBNwQTAQgAIQUCWHFbTgIbAwULCQgHAgYVCAkK
CwIEFgIDAQIeAQIXgAAKCRCG99Ce5zTmIwTmB/9/S4rmwU6efDgEaBDwBDbOfLBA
P2+kDpabjG4K+V4NSvDqlPN49KrI7C21jHghAa2VuTPbSZVQ9ziUd5DjX9OuXov8
CYVG+rrlG1UadHS8SBpgw0gNylEvo9/U6u0hl8mrbVOlpzu+eE+e4cMTHax2y580
fC2xmnM8wKgyRFEyVc6ilWU+UNTAeUFlg0YfU3cV1Ut4DzVFfamtNYg0p7Q/9MSy
VgFpt5C2U5prk4wi++51OgrtaNhMrUhzYXLINWVF6IrXhQ+mkI/FWXUZ0oyVo55v
+dQzuds/gos90q+tKyE514pYAmwQSftSjf+RmHOMpPQyMZZKSywrz4vlfveDuQEN
BFhxW04BCACs5bXq73MDb2+AsvNL2XkkbnzmE4K3k0gejB9OxrO+puAZn3wWyYIk
b0Op8qVUh+/FIiW/uFfmdFD8BypC3YkCNfg6e74f5TT3qQciccpMGy62teo3jfhT
T8E1OL1i76ALq7eNbByJKiKLBrTUDM6BDIeRZBWXQMase4+aqUAP47Kd/ByPsmCh
/pzb6yPdDPKwkspELssdPXYI7enddjQsCPoBko0j8CTPgKqMTeCuKMXCtD2gtRBN
eoVj4cbjZoZvBh8oJktzbYA8FX8eKdxIXhSP9MoVOPSWhxIQdwzkzUPK+0vUV8jA
NBTnGOkrRJPOHGPJWFWnTUGrzvcwi7czABEBAAGJAR8EGAEIAAkFAlhxW04CGwwA
CgkQhvfQnuc05iMIswgAmzSpCHFGKdkFLdC673FidJcL8adKFTO5Mpyholc5N8vG
ROJbpso+DpssF14NKoBfBWqPRgHxYzHakxHiNf0R2+EEwXH3rblzpx3PXzB0OgNe
T9T0UStrGgc9nZ8nZVURHZZ2z5zakEWS+rB2TiSxz3YArR3wiTHQW49G09uZvfp6
5Mim2w+eUxbQ689eT0DlDI1d2eDP/j5lrv1elsg3kBE2Awzdvi8DdGUpMFrSsYJw
WS85uZrwbeAs/nPO62wNIvAbbRsWnDg3AV3vc02eRvy52tTBY1W/67N02M4AxgPd
ukDDFZMifwa03yTHD/a57O4dFOnzsEVojBnbzQ7W7w==
=HKlF
-----END PGP PUBLIC KEY BLOCK-----
EOF

    if import_gpg_key "$tmp_key"; then
        rm -f "$tmp_key"
        echo -e "${GREEN}GPG 密钥使用内置备用公钥${NC}"
        return 0
    fi

    rm -f "$tmp_key"
    echo -e "${RED}错误: 无法导入 XanMod GPG 密钥${NC}"
    exit 1
}

add_xanmod_repo() {
    echo -e "${GREEN}正在添加 XanMod 内核仓库...${NC}"

    mkdir -p /etc/apt/keyrings
    install_xanmod_gpg_key

    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" \
        | tee /etc/apt/sources.list.d/xanmod-release.list

    apt-get update -qq

    echo -e "${GREEN}XanMod 仓库添加成功${NC}"
}

detect_psabi_level() {
    local flags level=0

    flags=$(grep -m1 '^flags[[:space:]]*:' /proc/cpuinfo | cut -d: -f2-)

    match_flags() {
        local flag
        for flag in "$@"; do
            echo "$flags" | grep -q "$flag" || return 1
        done
        return 0
    }

    if match_flags lm cmov cx8 fpu fxsr mmx syscall sse2; then
        level=1
        if match_flags cx16 lahf popcnt sse4_1 sse4_2 ssse3; then
            level=2
            if match_flags avx avx2 bmi1 bmi2 f16c fma abm movbe xsave; then
                level=3
            fi
        fi
    fi

    if [ "$level" -eq 0 ]; then
        echo -e "${YELLOW}无法识别 CPU 级别，默认 x86-64-v3${NC}" >&2
        level=3
    fi

    echo "$level"
}

detect_kernel_package() {
    local level candidates=() pkg

    echo -e "${GREEN}正在检测 CPU 架构级别...${NC}" >&2

    level=$(detect_psabi_level)
    echo -e "CPU supports x86-64-v${level}" >&2

    if [ "$level" -ge 3 ]; then
        candidates=(linux-xanmod-x64v3 linux-xanmod-edge-x64v3 linux-xanmod-lts-x64v3)
    elif [ "$level" -eq 2 ]; then
        candidates=(linux-xanmod-x64v2 linux-xanmod-edge-x64v2 linux-xanmod-lts-x64v2)
    else
        candidates=(linux-xanmod-lts-x64v1)
    fi

    for pkg in "${candidates[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            echo "$pkg"
            return 0
        fi
    done

    echo -e "${RED}错误: 仓库中未找到匹配的 XanMod 内核包${NC}" >&2
    exit 1
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
