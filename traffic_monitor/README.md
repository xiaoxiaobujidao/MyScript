# 网络流量监控脚本

提供两个脚本，监控逻辑相同（入站 + 出站累计流量），达到阈值后的行为不同：

| 脚本 | 达到阈值后的行为 |
| --- | --- |
| `traffic_shutdown.sh` | 等待 10 秒后关机 |
| `traffic_wait.sh` | 以退出码 `0`（true）退出，不关机，方便其他程序继续处理 |

## 使用方法

### 在线调用（推荐）

```bash
# 达到阈值后关机
curl -s https://raw.githubusercontent.com/xiaoxiaobujidao/MyScript/main/traffic_monitor/traffic_shutdown.sh | bash -s -- <流量阈值(GB)>

# 示例：当出入站总流量达到 100GB 时关机
curl -s https://raw.githubusercontent.com/xiaoxiaobujidao/MyScript/main/traffic_monitor/traffic_shutdown.sh | bash -s -- 100

# 达到阈值后成功退出（不关机）
curl -s https://raw.githubusercontent.com/xiaoxiaobujidao/MyScript/main/traffic_monitor/traffic_wait.sh | bash -s -- <流量阈值(GB)>

# 示例：流量用尽后再执行后续命令
curl -s https://raw.githubusercontent.com/xiaoxiaobujidao/MyScript/main/traffic_monitor/traffic_wait.sh | bash -s -- 100 && echo "流量已用尽"
```

> **提示**：使用在线脚本时，建议使用 tmux 或类似工具，以防止网络异常导致的连接中断。

### 本地调用

```bash
# 达到阈值后关机
./traffic_shutdown.sh <流量阈值(GB)>
./traffic_shutdown.sh 100

# 达到阈值后成功退出，再交给后续程序处理
./traffic_wait.sh <流量阈值(GB)>
./traffic_wait.sh 100 && ./your_followup.sh
```

### 与其他程序配合（`traffic_wait.sh`）

退出码约定：

- `0`：流量已达到阈值，可继续后续处理
- `1`：参数错误，或被 `Ctrl+C` / `SIGTERM` 中断（不会误触发后续逻辑）

```bash
# 方式一：&& 串联
./traffic_wait.sh 100 && systemctl stop my-service

# 方式二：if 判断
if ./traffic_wait.sh 100; then
    echo "流量已用尽，开始收尾"
    # 后续处理...
fi
```

## 功能特点

1. **实时监控**：每 5 秒检查一次网络流量
2. **精确计算**：从脚本启动时开始计算流量增量
3. **多接口支持**：自动统计所有网络接口的流量（排除回环接口和虚拟网口）
4. **虚拟网口过滤**：自动排除 Docker、veth、br-、virbr、vmnet、tun、tap 等虚拟网口
5. **友好显示**：实时显示当前流量使用情况和百分比，启动时显示被监控的网口列表
6. **日志记录**：自动记录监控日志到临时文件
7. **两种收尾方式**：`traffic_shutdown.sh` 达到阈值后等待 10 秒再关机（可按 Ctrl+C 取消）；`traffic_wait.sh` 达到阈值后立即以成功状态退出，不关机

## 显示信息

脚本运行时会显示：
- 流量阈值设置
- 启动时的初始流量
- 实时流量增量（入站/出站/总计）
- 流量使用百分比
- 状态文件和日志文件位置

## 注意事项

1. **权限要求**：`traffic_shutdown.sh` 的关机操作需要 root 权限，如果以普通用户运行，脚本会尝试使用 sudo；`traffic_wait.sh` 不关机，无需 root
2. **依赖工具**：需要 `bc` 计算器工具，脚本会自动检测并安装
3. **状态文件**：脚本会在 `/tmp/` 目录创建临时状态文件和日志文件
4. **停止监控**：按 `Ctrl+C` 可以随时停止监控。`traffic_wait.sh` 被中断时以失败状态退出，避免后续程序误判为已达阈值
5. **流量统计**：统计的是所有物理网络接口的总流量，自动排除：
   - 回环接口 (lo)
   - Docker 网口 (docker0, docker-xxx)
   - 虚拟以太网接口 (veth*)
   - 网桥接口 (br-*)
   - libvirt 虚拟网桥 (virbr*)
   - VMware 虚拟网口 (vmnet*)
   - TUN/TAP 设备 (tun*, tap*)
   - 其他虚拟网络接口

## 示例输出

```
========================================
  网络流量监控已启动
========================================
流量阈值: 100 GB
监控的网口: eth0 ens33
已排除虚拟网口: docker, veth, br-, virbr, vmnet, tun, tap 等
启动时入站流量: 1.23 GB
启动时出站流量: 0.45 GB
状态文件: /tmp/traffic_monitor_12345.status
日志文件: /tmp/traffic_monitor_12345.log
========================================

开始监控网络流量...
按 Ctrl+C 可停止监控

[14:30:15] 入站: 2.34 GB | 出站: 1.56 GB | 总计: 3.90 GB (3.90%)
[14:30:20] 入站: 2.35 GB | 出站: 1.57 GB | 总计: 3.92 GB (3.92%)
...
```

## 技术说明

- 使用 `/proc/net/dev` 获取网络接口流量统计
- 自动排除回环接口（lo）
- 支持多个网络接口的流量汇总
- 处理计数器溢出的情况
