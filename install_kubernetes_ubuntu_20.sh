# How to use?
#       wget https://raw.githubusercontent.com/Davidnovarro/utility/main/install_kubernetes_ubuntu_20.sh
#       sh install_kubernetes_ubuntu_20.sh
# If not a master node then, on master node create token to join the cluster: kubeadm token create --print-join-command
# Instructions are from:
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
INSTALL_CALICO_VERSION='v3.26.1'


if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

ReadYesNo "Is this a Master Node?"
IS_MASTER_NODE=$YES

ReadTextInput "Please input a unique name for a node"
HOST_NAME=$TEXT_INPUT
sudo hostnamectl set-hostname $HOST_NAME

#ISSUE: In case if this error is shown "sudo: unable to resolve host ${HOST_NAME}"
#FIX: Set or Change the HOST_NAME in /etc/hosts so the line looks something like this "127.0.0.1 $HOST_NAME" (https://www.globo.tech/learning-center/sudo-unable-to-resolve-host-explained/)

sudo apt update && sudo apt upgrade -y
sudo apt-get install ca-certificates curl gnupg ufw

#Adding apt repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo $(lsb_release -cs))" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# EXTERNAL_IP=$(host myip.opendns.com resolver1.opendns.com | grep "myip.opendns.com has" | awk '{print $4}')
EXTERNAL_IP=$(curl checkip.amazonaws.com)

#Disable Firewall
ufw disable

#Disable swap
swapoff -a; sed -i '/swap/d' /etc/fstab

#Prepeare to install container runtime : https://kubernetes.io/docs/setup/production-environment/container-runtimes/
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

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

#Install containerd as container runtime
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo sysctl --system

sudo apt install curl gnupg2 software-properties-common apt-transport-https ca-certificates -y
#Adding apt repo
sudo apt update
sudo apt install containerd.io -y
mkdir -p /etc/containerd
containerd config default>/etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

#Kubernetes Setup
#Add Apt repository
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=$INSTALL_KUBE_VERSION kubeadm=$INSTALL_KUBE_VERSION kubectl=$INSTALL_KUBE_VERSION
sudo apt-mark hold kubelet kubeadm kubectl

if $IS_MASTER_NODE; then
  #Initialize Kubernetes Cluster 
  kubeadm init --apiserver-advertise-address=$EXTERNAL_IP --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=all --apiserver-cert-extra-sans=$EXTERNAL_IP
  
  export KUBECONFIG='/etc/kubernetes/admin.conf'
  #Remove the taints on the master so that you can schedule pods on it.
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>/dev/null
  kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null
 

  #Deploy Calico network
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$INSTALL_CALICO_VERSION/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$INSTALL_CALICO_VERSION/manifests/custom-resources.yaml

  #Cluster join command
  kubeadm token create --print-join-command

  #Copy the config file to main folder
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
else
    # Follow the join instructions manually and then run the commands commented below
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>/dev/null
    # kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null
fi

echo "alias k='kubectl'" | tee ~/.bash_aliases
source ~/.bash_aliases