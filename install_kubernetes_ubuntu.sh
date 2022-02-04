# Original: https://github.com/justmeandopensource/kubernetes/tree/master/docs
# wget https://raw.githubusercontent.com/Davidnovarro/utility/main/install_kubernetes_ubuntu.sh
# sh install_kubernetes_ubuntu.sh
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

INSTALL_DOCKER_CE_VERSION='5:19.03.10~3-0~ubuntu-focal'
INSTALL_KUBE_VERSION='1.21.9-00'
INSTALL_CALICO_VERSION='v3.22'


if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

ReadYesNo "Is this a Master Node?"
IS_MASTER_NODE=$YES

ReadTextInput "Please input a unique name for a node"

EXTERNAL_IP=$(host myip.opendns.com resolver1.opendns.com | grep "myip.opendns.com has" | awk '{print $4}')

sudo hostnamectl set-hostname $TEXT_INPUT

#Disable Firewall
ufw disable

#Disable swap
swapoff -a; sed -i '/swap/d' /etc/fstab


#Update sysctl settings for Kubernetes networking
sysctl_settings=$(cat /etc/sysctl.d/kubernetes.conf | grep "net.bridge.bridge-nf-call-ip6tables\|net.bridge.bridge-nf-call-iptables")

if [ ${#sysctl_settings} -gt 0 ]; then echo "Skipping: sysctl settings for Kubernetes networking" ;
else
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
fi


#Install docker engine
{
  sudo apt-get remove docker docker-engine docker.io containerd runc
  apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt update
  apt install -y docker-ce=$INSTALL_DOCKER_CE_VERSION containerd.io
}

#Kubernetes Setup
#Add Apt repository
{
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
}

#Install Kubernetes components
apt update && apt install -y kubeadm=$INSTALL_KUBE_VERSION kubelet=$INSTALL_KUBE_VERSION kubectl=$INSTALL_KUBE_VERSION

if $IS_MASTER_NODE; then
  #Initialize Kubernetes Cluster
  kubeadm init --apiserver-advertise-address=$EXTERNAL_IP --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=all
  export KUBECONFIG='/etc/kubernetes/admin.conf'
  #Remove the taints on the master so that you can schedule pods on it.
  kubectl taint nodes --all node-role.kubernetes.io/master-
  #Deploy Calico network
  kubectl create -f https://docs.projectcalico.org/$INSTALL_CALICO_VERSION/manifests/calico.yaml
  #Cluster join command
  kubeadm token create --print-join-command
fi

#Remove the taints on the master so that you can schedule pods on it.
kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null