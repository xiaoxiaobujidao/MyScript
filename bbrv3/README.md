# BBRv3

基于 [XanMod 内核](https://xanmod.org/) 安装并启用 Google BBRv3 拥塞控制算法。

> **Warning**
> 如非必要，请勿在生产环境使用此脚本，可能导致严重损失！

## 一键安装

```bash
curl -s "https://raw.githubusercontent.com/xiaoxiaobujidao/MyScript/main/bbrv3/bbrv3.sh?date=$(date +%s)" | bash -
```

建议使用 tmux 等工具运行，防止网络异常导致 SSH 断开。

## 脚本做了什么

1. 添加 XanMod 官方 APT 仓库（GPG 密钥 + 发行版代号）
2. 通过官方 psABI 检测脚本自动选择匹配的内核包（x64v3 / x64v2 / lts-x64v1）
3. 安装 XanMod MAIN 分支内核（默认 `linux-xanmod-x64v3`）
4. 写入 `/etc/sysctl.d/99-bbr.conf` 启用 BBRv3（`tcp_congestion_control=bbr` + `default_qdisc=fq`）

## 重启后验证

```bash
uname -r
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
cat /proc/sys/net/ipv4/tcp_available_congestion_control
```

预期输出：`tcp_congestion_control = bbr`，`default_qdisc = fq`。

## 说明

- XanMod 内核已将 BBRv1 模块升级为 BBRv3，sysctl 名称仍为 `bbr`（非 `bbr3`）
- 支持的发行版代号见 [xanmod.org](https://xanmod.org/)（如 bookworm、trixie、noble 等）
- 如需编译外部内核模块（NVIDIA 等），可额外安装：`apt install --no-install-recommends dkms libelf-dev clang lld llvm`
