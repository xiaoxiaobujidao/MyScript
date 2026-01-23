#!/bin/bash

# 网络流量监控脚本 - 达到指定流量后自动关机
# 用法: ./traffic_shutdown.sh <流量阈值(GB)>

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -eq 0 ]; then
    echo -e "${RED}错误: 请指定流量阈值${NC}"
    echo "用法: $0 <流量阈值(GB)>"
    echo "示例: $0 100  # 当出入站总流量达到 100GB 时关机"
    exit 1
fi

# 验证参数是否为有效数字
if ! [[ "$1" =~ ^[0-9]+\.?[0-9]*$ ]] || [[ "$1" =~ ^0+\.?0*$ ]]; then
    echo -e "${RED}错误: 流量阈值必须是大于 0 的数字${NC}"
    exit 1
fi

THRESHOLD_GB=$1
THRESHOLD_BYTES=$(echo "scale=0; $THRESHOLD_GB * 1024 * 1024 * 1024" | bc 2>/dev/null || echo "")

# 验证计算结果
if [ -z "$THRESHOLD_BYTES" ] || ! [[ "$THRESHOLD_BYTES" =~ ^[0-9]+$ ]] || [ "$THRESHOLD_BYTES" = "0" ]; then
    echo -e "${RED}错误: 无法计算流量阈值，请检查输入参数和 bc 工具${NC}"
    exit 1
fi

# 检查 bc 是否安装
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}警告: bc 未安装，正在安装...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y bc
    elif command -v yum &> /dev/null; then
        sudo yum install -y bc
    else
        echo -e "${RED}错误: 无法自动安装 bc，请手动安装${NC}"
        exit 1
    fi
fi

# 状态文件路径
STATUS_FILE="/tmp/traffic_monitor_$$.status"
LOG_FILE="/tmp/traffic_monitor_$$.log"

# 清理函数
cleanup() {
    echo -e "\n${YELLOW}正在清理...${NC}"
    rm -f "$STATUS_FILE" "$LOG_FILE"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 检查是否为虚拟网口
is_virtual_interface() {
    local interface=$1
    
    # 排除虚拟网口模式
    # docker: docker0, docker-xxx
    # veth: veth开头的虚拟以太网接口
    # br-: 网桥接口 (如 br-xxx)
    # virbr: libvirt虚拟网桥
    # vmnet: VMware虚拟网口
    # tun/tap: TUN/TAP虚拟网络设备
    # 其他常见的虚拟接口前缀
    
    if [[ "$interface" =~ ^(lo|docker|veth|br-|virbr|vmnet|tun|tap|wg|ppp|wwan) ]] || \
       [[ "$interface" =~ docker ]] || \
       [[ "$interface" =~ ^veth ]] || \
       [[ "$interface" =~ ^br- ]] || \
       [[ "$interface" =~ ^virbr ]] || \
       [[ "$interface" =~ ^vmnet ]] || \
       [[ "$interface" =~ ^tun[0-9]+ ]] || \
       [[ "$interface" =~ ^tap[0-9]+ ]]; then
        return 0  # 是虚拟接口
    fi
    
    return 1  # 不是虚拟接口
}

# 获取所有网络接口的总流量（字节）
get_total_traffic() {
    local total_rx=0
    local total_tx=0
    
    # 读取 /proc/net/dev，跳过前两行（标题行）
    while IFS= read -r line; do
        # 跳过回环接口和标题行
        if [[ "$line" =~ ^[[:space:]]*lo: ]] || [[ "$line" =~ ^[[:space:]]*Inter- ]] || [[ "$line" =~ ^[[:space:]]*face ]]; then
            continue
        fi
        
        # 解析流量数据
        # 格式: interface: rx_bytes rx_packets ... tx_bytes tx_packets ...
        # 使用 awk 解析：先以冒号分隔获取接口名，再以空格分隔获取数值
        # /proc/net/dev 格式：interface: rx_bytes rx_packets rx_errs rx_drop rx_fifo rx_frame rx_compressed rx_multicast tx_bytes tx_packets ...
        local interface=$(echo "$line" | awk -F: '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')
        
        # 跳过空接口名
        if [ -z "$interface" ]; then
            continue
        fi
        
        # 跳过虚拟网口
        if is_virtual_interface "$interface"; then
            continue
        fi
        
        # 提取 rx_bytes (冒号后的第1个字段) 和 tx_bytes (冒号后的第9个字段)
        # 使用 awk 处理冒号后的部分，字段编号从1开始
        local rx_bytes=$(echo "$line" | awk -F: '{print $2}' | awk '{print $1}')
        local tx_bytes=$(echo "$line" | awk -F: '{print $2}' | awk '{print $9}')
        
        # 验证是否为有效数字
        if [[ "$rx_bytes" =~ ^[0-9]+$ ]] && [[ "$tx_bytes" =~ ^[0-9]+$ ]]; then
            total_rx=$((total_rx + rx_bytes))
            total_tx=$((total_tx + tx_bytes))
        fi
    done < /proc/net/dev
    
    echo "$total_rx $total_tx"
}

# 格式化字节数为可读格式
format_bytes() {
    local bytes=$1
    
    # 验证输入是否为有效数字
    if [ -z "$bytes" ] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return
    fi
    
    if (( bytes >= 1099511627776 )); then
        local result=$(echo "scale=2; $bytes / 1099511627776" | bc 2>/dev/null)
        echo "${result:-0} TB"
    elif (( bytes >= 1073741824 )); then
        local result=$(echo "scale=2; $bytes / 1073741824" | bc 2>/dev/null)
        echo "${result:-0} GB"
    elif (( bytes >= 1048576 )); then
        local result=$(echo "scale=2; $bytes / 1048576" | bc 2>/dev/null)
        echo "${result:-0} MB"
    elif (( bytes >= 1024 )); then
        local result=$(echo "scale=2; $bytes / 1024" | bc 2>/dev/null)
        echo "${result:-0} KB"
    else
        echo "$bytes B"
    fi
}

# 获取被监控的网络接口列表
get_monitored_interfaces() {
    local interfaces=()
    
    while IFS= read -r line; do
        # 跳过回环接口和标题行
        if [[ "$line" =~ ^[[:space:]]*lo: ]] || [[ "$line" =~ ^[[:space:]]*Inter- ]] || [[ "$line" =~ ^[[:space:]]*face ]]; then
            continue
        fi
        
        # 解析接口名称
        if [[ "$line" =~ ^[[:space:]]*([^:]+): ]]; then
            interface="${BASH_REMATCH[1]}"
            
            # 只包含非虚拟接口
            if ! is_virtual_interface "$interface"; then
                interfaces+=("$interface")
            fi
        fi
    done < /proc/net/dev
    
    echo "${interfaces[@]}"
}

# 初始化：记录启动时的流量
init_traffic() {
    local traffic=$(get_total_traffic)
    local start_rx=$(echo "$traffic" | awk '{print $1}')
    local start_tx=$(echo "$traffic" | awk '{print $2}')
    local monitored_interfaces=$(get_monitored_interfaces)
    
    echo "$start_rx $start_tx" > "$STATUS_FILE"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  网络流量监控已启动${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}流量阈值: ${THRESHOLD_GB} GB${NC}"
    echo -e "${BLUE}监控的网口: ${monitored_interfaces}${NC}"
    echo -e "${YELLOW}已排除虚拟网口: docker, veth, br-, virbr, vmnet, tun, tap 等${NC}"
    echo -e "${BLUE}启动时入站流量: $(format_bytes $start_rx)${NC}"
    echo -e "${BLUE}启动时出站流量: $(format_bytes $start_tx)${NC}"
    echo -e "${BLUE}状态文件: $STATUS_FILE${NC}"
    echo -e "${BLUE}日志文件: $LOG_FILE${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 记录到日志
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 监控启动 - 阈值: ${THRESHOLD_GB}GB, 监控网口: ${monitored_interfaces}, 初始入站: $(format_bytes $start_rx), 初始出站: $(format_bytes $start_tx)" >> "$LOG_FILE"
}

# 检查流量并判断是否需要关机
check_traffic() {
    if [ ! -f "$STATUS_FILE" ]; then
        echo -e "${RED}错误: 状态文件不存在${NC}"
        return 1
    fi
    
    local start_data=$(cat "$STATUS_FILE")
    local start_rx=$(echo "$start_data" | awk '{print $1}')
    local start_tx=$(echo "$start_data" | awk '{print $2}')
    
    local current_traffic=$(get_total_traffic)
    local current_rx=$(echo "$current_traffic" | awk '{print $1}')
    local current_tx=$(echo "$current_traffic" | awk '{print $2}')
    
    # 计算增量（处理计数器溢出）
    local rx_diff=$((current_rx - start_rx))
    local tx_diff=$((current_tx - start_tx))
    
    # 如果差值为负，可能是计数器溢出，取绝对值
    if (( rx_diff < 0 )); then
        rx_diff=$current_rx
    fi
    if (( tx_diff < 0 )); then
        tx_diff=$current_tx
    fi
    
    local total_diff=$((rx_diff + tx_diff))
    local remaining_bytes=0
    if [ -n "$THRESHOLD_BYTES" ] && [ "$THRESHOLD_BYTES" -gt 0 ] 2>/dev/null; then
        remaining_bytes=$((THRESHOLD_BYTES - total_diff))
        if (( remaining_bytes < 0 )); then
            remaining_bytes=0
        fi
    fi
    
    # 安全地计算 GB 值，处理空值或无效值
    local total_diff_gb="0"
    if [ -n "$total_diff" ] && [ "$total_diff" -ge 0 ] 2>/dev/null; then
        total_diff_gb=$(echo "scale=4; $total_diff / 1073741824" | bc 2>/dev/null || echo "0")
    fi
    
    # 安全地检查是否达到阈值
    local threshold_reached="0"
    if [ -n "$total_diff" ] && [ -n "$THRESHOLD_BYTES" ] && [ "$total_diff" -ge 0 ] 2>/dev/null && [ "$THRESHOLD_BYTES" -gt 0 ] 2>/dev/null; then
        threshold_reached=$(echo "$total_diff >= $THRESHOLD_BYTES" | bc 2>/dev/null || echo "0")
    fi
    
    # 显示当前状态
    local rx_formatted=$(format_bytes $rx_diff)
    local tx_formatted=$(format_bytes $tx_diff)
    local total_formatted=$(format_bytes $total_diff)
    local remaining_formatted=$(format_bytes $remaining_bytes)
    
    # 安全地计算百分比，避免除以零
    local percentage="0"
    if [ -n "$total_diff_gb" ] && [ -n "$THRESHOLD_GB" ] && [ "$THRESHOLD_GB" != "0" ]; then
        percentage=$(echo "scale=2; $total_diff_gb * 100 / $THRESHOLD_GB" | bc 2>/dev/null || echo "0")
    fi
    
    echo -e "${BLUE}[$(date '+%H:%M:%S')] 入站: $rx_formatted | 出站: $tx_formatted | 总计: $total_formatted (${percentage}%) | 余量: $remaining_formatted${NC}"
    
    # 记录到日志
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 入站增量: $rx_formatted, 出站增量: $tx_formatted, 总计: $total_formatted (${percentage}%), 余量: $remaining_formatted" >> "$LOG_FILE"
    
    # 检查是否达到阈值
    if [ "$threshold_reached" = "1" ]; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  流量阈值已达到！${NC}"
        echo -e "${RED}========================================${NC}"
        echo -e "${YELLOW}总流量: $total_formatted${NC}"
        echo -e "${YELLOW}阈值: ${THRESHOLD_GB} GB${NC}"
        echo -e "${RED}系统将在 10 秒后关机...${NC}"
        echo -e "${RED}按 Ctrl+C 可取消${NC}"
        echo -e "${RED}========================================${NC}"
        
        # 记录到日志
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 流量阈值已达到！总流量: $total_formatted, 准备关机..." >> "$LOG_FILE"
        
        # 等待10秒后关机
        sleep 10
        
        # 检查是否为 root 用户
        if [ "$EUID" -eq 0 ]; then
            shutdown -h now
        else
            echo -e "${YELLOW}需要 root 权限才能关机，尝试使用 sudo...${NC}"
            sudo shutdown -h now
        fi
        
        return 0
    fi
    
    return 1
}

# 主循环
main() {
    init_traffic
    
    echo -e "${GREEN}开始监控网络流量...${NC}"
    echo -e "${YELLOW}按 Ctrl+C 可停止监控${NC}"
    echo ""
    
    # 主循环：每5秒检查一次
    while true; do
        if check_traffic; then
            # 如果达到阈值，check_traffic 会执行关机，这里不会执行到
            break
        fi
        sleep 5
    done
}

# 运行主函数
main
