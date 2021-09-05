#!/bin/bash
#

export custom_user=ubuntu
export docker_version=18.09.9;
export docker_compose_version=1.25.5
export node_exporter_version=0.18.1

sudo apt-get remove docker docker-engine docker.io containerd runc -y;

sudo apt-get update -y;

sudo apt-get install apt-transport-https ca-certificates \
    curl software-properties-common bash-completion  gnupg-agent git -y;

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -;

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update -y;

install_version=$( apt-cache madison docker-ce | grep ${docker_version} | awk '{print $3}' );

sudo apt-get install docker-ce=${install_version} docker-ce-cli=${install_version} containerd.io --allow-downgrades -y

sudo usermod -aG docker $custom_user;

sudo systemctl enable docker;

apt-get autoremove  -y

sudo apt-mark hold docker-ce docker-ce-cli

cat > /etc/docker/daemon.json <<EOF
{
    "oom-score-adjust": -1000,
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "100m",
      "max-file": "3"
    },
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "storage-driver": "overlay2",
    "storage-opts": [
       "overlay2.override_kernel_check=true"
    ]
}
EOF

systemctl daemon-reload && systemctl restart docker

sudo curl -L "https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

cat >> /etc/sysctl.conf<<EOF
net.ipv4.ip_forward=1
net.ipv4.neigh.default.gc_thresh1=4096
net.ipv4.neigh.default.gc_thresh2=6144
net.ipv4.neigh.default.gc_thresh3=8192
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
vm.swappiness=0
EOF

echo br_netfilter >> /etc/modules && modprobe br_netfilter
sysctl -p

cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65536
EOF

# 关闭交换内存
swapoff -a
sed -ir 's/.*swap/#&/g' /etc/fstab
rm -Rf /swap.img

# 解决 Ubuntu 或 Debian 操作系统下 docker swap limit 提示
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"/' /etc/default/grub
update-grub

# 添加 Ubuntu 阿里云 kubernetes 软件仓库
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" >>/etc/apt/sources.list.d/kubernetes.list
apt-get update

## 配置sudo免密
echo "$custom_user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers


# install node exporter
useradd -M -r -s /bin/false node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz
tar xzf node_exporter-${node_exporter_version}.linux-amd64.tar.gz
cp node_exporter-${node_exporter_version}.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start node_exporter.service
systemctl enable node_exporter.service
