#!/bin/bash
# 获取版本
apt update
apt install gnupg curl mawk -y
version=$(curl -s https://dl.xanmod.org/check_x86-64_psabi.sh | awk -f -)
version=$(echo ${version: -1})
curl https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg

echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list

apt update && apt install -y linux-xanmod-x64v$version

# 设置 bbrv3

cat >>/etc/sysctl.conf <<EOF

net.core.default_qdisc=fq_pie

net.ipv4.tcp_congestion_control=bbr

EOF

cat >>/etc/sysctl.d/10-enable-bbr.conf <<EOF 
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864

net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

net.ipv4.tcp_mtu_probing=1
EOF


cat >>/etc/sysctl.conf <<EOF 
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864

net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

net.ipv4.tcp_mtu_probing=1
EOF


reboot
