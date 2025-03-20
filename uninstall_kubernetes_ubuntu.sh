# Original: https://github.com/justmeandopensource/kubernetes/tree/master/docs
# wget https://raw.githubusercontent.com/Davidnovarro/utility/main/uninstall_kubernetes_ubuntu.sh
# sh uninstall_kubernetes_ubuntu.sh
if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

# If Master Node
# kubectl delete all --all
# kubectl delete all --all -n {namespace}
# If the cluster is node, First delete it from master
# kubectl drain <node name> --delete-emptydir-data --ignore-daemonsets
# kubectl delete node <node name>


printf 'y\n' | kubeadm reset

apt-get purge -y docker-ce containerd.io
apt-get purge -y kubeadm kubectl kubelet kubernetes-cni kube*
sudo apt-get autoremove -y

rm -rf /etc/cni/net.d
rm -rf /etc/kubernetes
rm -rf ~/.kube


sudo systemctl stop containerd
sudo systemctl disable containerd
sudo apt-get remove --purge -y containerd

sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/containerd
sudo rm -rf /usr/local/bin/containerd*

iptables -F
ufw enable