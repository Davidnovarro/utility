if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

printf 'y\n' | kubeadm reset

apt-get purge -y docker-ce containerd.io
apt-get purge -y kubeadm kubectl kubelet kubernetes-cni kube*
sudo apt-get autoremove -y

rm -rf /etc/cni/net.d
rm -rf /etc/kubernetes
rm -rf ~/.kube

iptables -F
ufw enable