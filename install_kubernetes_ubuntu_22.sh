# How to use?
#       wget https://raw.githubusercontent.com/Davidnovarro/utility/main/install_kubernetes_ubuntu_22.sh
#       sh install_kubernetes_ubuntu_22.sh
# If not a master node then, on master node create token to join the cluster: kubeadm token create --print-join-command
# Instructions are from:
# https://www.youtube.com/watch?v=7k9Rdlx30OY&ab_channel=Geekhead
# https://www.itsgeekhead.com/tuts/kubernetes-126-ubuntu-2204.txt
# https://github.com/justmeandopensource/kubernetes/tree/master/docs
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/
# https://docs.docker.com/engine/install/ubuntu/
# https://projectcalico.docs.tigera.io/getting-started/kubernetes/quickstart
#Get script location base path
BASE_PATH=$(readlink -f "$0" | xargs dirname)

#region FUNCTIONS
ReadYesNo()
{
    while true; do
        read -p "$1 (Y/N)" yn
        case $yn in
            [Yy]* ) 
                YES=true
                NO=false
            break;;
            [Nn]* ) 
                YES=false
                NO=true
            break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

ReadFolderPath()
{
    while true; do
        read -p "$1 : " FOLDER_PATH
        
        if [[ "$FOLDER_PATH" != */ ]]
        then
            FOLDER_PATH="${FOLDER_PATH}/"
        fi

        if [[ -d "$FOLDER_PATH" ]]
        then
            break
        else
            echo "Folder path $FOLDER_PATH DOES NOT exists." 
        fi

    done
}

GetRelativeOrReadFolderPath()
{
    local relative=$1
    if [[ "$relative" != */ ]]
    then
        relative="${relative}/"
    fi
    
    if [[ "$relative" != /* ]]
    then
        relative="/${relative}"
    fi

    if [[ -d "${BASE_PATH}${relative}" ]]
    then
        FOLDER_PATH="${BASE_PATH}${relative}"
    else
        echo "Unable to get the default value using the relative path ${relative}"
        ReadFolderPath "$2"
    fi
}

ReadFilePath()
{
    while true; do
        read -p "$1 : " FILE_PATH

        if [[ -f "$FILE_PATH" ]]
        then
            break
        else
            echo "File path $FILE_PATH DOES NOT exists." 
        fi

    done
}

GetRelativeOrReadFilePath()
{
    local relative=$1
    
    if [[ "$relative" != /* ]]
    then
        relative="/${relative}"
    fi

    if [[ -f "${BASE_PATH}${relative}" ]]
    then
        FILE_PATH="${BASE_PATH}${relative}"
    else
        echo "Unable to get the default value using the relative path ${relative}"
        ReadFilePath "$2"
    fi
}

ReadTextInput()
{
    read -p "$1 : " TEXT_INPUT
}

RequireCommand()
{
    if ! [ -x "$(command -v $1)" ]; then
        echo "Error: $1 is not installed."
        exit 1
    fi
}

RequireFile()
{
  if ! [ -f "$1" ];then
      echo "File does not exist $1"
      exit 1
  fi
}

RequireFolder()
{
    if ! [ -d "$1" ];then
        echo "Folder does not exist $1"
        exit 1
    fi
}

#endregion

export DEBIAN_FRONTEND="noninteractive"

#HOW TO LIST ALL THE VEERSIONS?
#apt update
#apt-cache madison docker-ce
#apt-cache madison kubeadm
INSTALL_KUBE_VERSION='1.27.4-00'
INSTALL_CALICO_VERSION='3.26.1'
CONTAINERD_VERSION="1.7.3"
RUNC_VERSION="1.1.9"
CNI_PLUGINS_VERSION="1.3.0"
POD_NETWORK_CIDR='192.168.0.0/16'


if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

ReadYesNo "Is this a Master Node?"
IS_MASTER_NODE=$YES

ReadTextInput "Please input a unique name for a node"
HOST_NAME=$TEXT_INPUT
OLD_HOST_NAME=$(hostname -s)
hostnamectl set-hostname $HOST_NAME

apt-get update
apt-get install -y apt-transport-https ca-certificates curl

EXTERNAL_IP=$(curl checkip.amazonaws.com)

# Add required lines to /etc/hosts if they do not exts already
if ! grep -q "localhost" "/etc/hosts"; then
  echo "127.0.0.1 localhost" >> "/etc/hosts"
  echo "::1 localhost" >> "/etc/hosts"
fi

if ! grep -q "ip6-localhost" "/etc/hosts"; then
  echo "# The following lines are desirable for IPv6 capable hosts" >> "/etc/hosts"
  echo "::1     ip6-localhost ip6-loopback" >> "/etc/hosts"
  echo "fe00::0 ip6-localnet" >> "/etc/hosts"
  echo "ff00::0 ip6-mcastprefix" >> "/etc/hosts"
  echo "ff02::1 ip6-allnodes" >> "/etc/hosts"
  echo "ff02::2 ip6-allrouters" >> "/etc/hosts"
fi

if ! grep -q "${EXTERNAL_IP}" "/etc/hosts" ; then
  echo "${EXTERNAL_IP} ${HOST_NAME}" >> "/etc/hosts"
fi

#Prepeare to install container runtime : https://kubernetes.io/docs/setup/production-environment/container-runtimes/
printf "overlay\nbr_netfilter\n" >> /etc/modules-load.d/containerd.conf

modprobe overlay
modprobe br_netfilter

printf "net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n" >> /etc/sysctl.d/99-kubernetes-cri.conf

sysctl --system

wget https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz -P /tmp/
tar Cxzvf /usr/local /tmp/containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -P /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd


wget https://github.com/opencontainers/runc/releases/download/v$RUNC_VERSION/runc.amd64 -P /tmp/
install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc

wget https://github.com/containernetworking/plugins/releases/download/v$CNI_PLUGINS_VERSION/cni-plugins-linux-amd64-v$CNI_PLUGINS_VERSION.tgz -P /tmp/
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin /tmp/cni-plugins-linux-amd64-v$CNI_PLUGINS_VERSION.tgz

mkdir -p /etc/containerd
#Changing the SystemdCgroup to true
containerd config default | sed -e 's|SystemdCgroup = false|SystemdCgroup = true|' | tee /etc/containerd/config.toml
if ! grep -q "SystemdCgroup = true" "/etc/containerd/config.toml"; then
  echo "Error: unable to set SystemdCgroup = true in /etc/containerd/config.toml file"
  exit 1
fi
systemctl restart containerd

#Disable Firewall
ufw disable

#Disable swap
swapoff -a; sed -i '/swap/d' /etc/fstab

apt-get update
apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet=$INSTALL_KUBE_VERSION kubeadm=$INSTALL_KUBE_VERSION kubectl=$INSTALL_KUBE_VERSION
apt-mark hold kubelet kubeadm kubectl

if $IS_MASTER_NODE; then
  #Initialize Kubernetes Cluster 
  kubeadm init --apiserver-advertise-address=$EXTERNAL_IP --pod-network-cidr=$POD_NETWORK_CIDR --ignore-preflight-errors=all --apiserver-cert-extra-sans=$EXTERNAL_IP --skip-token-print --skip-certificate-key-print
  
  export KUBECONFIG='/etc/kubernetes/admin.conf'
  #Remove the taints on the master so that you can schedule pods on it.
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>/dev/null
  kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null
 

  #Deploy Calico network
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v$INSTALL_CALICO_VERSION/manifests/tigera-operator.yaml
  curl https://raw.githubusercontent.com/projectcalico/calico/v$INSTALL_CALICO_VERSION/manifests/custom-resources.yaml | sed -e "s|192.168.0.0/16|${POD_NETWORK_CIDR}|" | kubectl create -f -

  #Copy the config file to main folder
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  #Print the cluster join command
  kubeadm token create --print-join-command
else
    # Follow the join instructions manually and then run the commands commented below
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>/dev/null
    # kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null
fi

#TODO: Delete the /tmp/ folder 