# How to use?
#       wget -q https://raw.githubusercontent.com/Davidnovarro/utility/main/install_kubernetes_ubuntu_22.sh
#       bash install_kubernetes_ubuntu_22.sh
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
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
BASE_PATH=$(readlink -f "$0" | xargs dirname)
#Make sure versions are compatible with each other
INSTALL_KUBE_VERSION='1.27.4-00'
INSTALL_CALICO_VERSION='3.26.1'
CONTAINERD_VERSION="1.7.3"
RUNC_VERSION="1.1.9"
CNI_PLUGINS_VERSION="1.3.0"
POD_NETWORK_CIDR='192.168.0.0/16'
# ALL_IPVS_OPTIONS="disabled sh rr wrr lc wlc lblc lblcr dh sed nq"
ALL_IPVS_OPTIONS="disabled rr sh"

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

# Sets the persistent variable
# arg1 is KEY, arg2 is VALUE
SetVariable()
{
    echo $2 | tee "$BASE_PATH/$1.txt" > /dev/null 2>/dev/null
}

# Gets the persistent variable if does not exist sets the default value
# arg1 is KEY, arg2 is the default value
# Usage example
# if [ $(GetVariable "my_key" 0) = 99 ]; then
#     echo "Value is 99"
# fi
GetVariable()
{ 
    if ! test -f "$BASE_PATH/$1.txt"; then
        echo $2
    else
        cat "$BASE_PATH/$1.txt"
    fi
}

# Sets the persistent variable
# arg1 is KEY
RemoveVariable()
{
    rm "$BASE_PATH/$1.txt"
}

#endregion

sudo apt-get -qq update -y
sudo apt-get -qq install curl -y
EXTERNAL_IP=$(curl -s checkip.amazonaws.com)

if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

echo "alias k='kubectl'" | tee ~/.bash_aliases > /dev/null 2>/dev/null
#echo 'Run this command to activate aliases: source ~/.bash_aliases'

if [ $(GetVariable "install_kubernetes_phase" 0) = "FINISHED" ]; then
    echo "Install phase is FINISHED"
    exit 0
fi

#region Install Phase 0
if [ $(GetVariable "install_kubernetes_phase" 0) = 0 ]; then
    echo "Starting install phase 0"

    ReadTextInput "Please input a unique name for a node"
    HOST_NAME=$TEXT_INPUT
    OLD_HOST_NAME=$(hostname -s)
    hostnamectl set-hostname $HOST_NAME

    sudo apt-get -qq update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl

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

    # Install IPVS
    sudo apt-get -qq update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y ipset ipvsadm
    #Adding kernel modules required by IPVS to load on boot time
    printf "ip_vs\nip_vs_rr\nip_vs_wrr\nip_vs_sh\nnf_conntrack\n" | tee /etc/modules-load.d/ipvs.conf > /dev/null 2>/dev/null
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh
    modprobe nf_conntrack

    # Install Containerd : https://kubernetes.io/docs/setup/production-environment/container-runtimes/
    #Adding kernel modules required by Containerd to load on boot time
    printf "overlay\nbr_netfilter\n" | tee /etc/modules-load.d/containerd.conf > /dev/null 2>/dev/null

    modprobe overlay
    modprobe br_netfilter

    printf "net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n" | tee /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null 2>/dev/null

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
    containerd config default | sed -e 's|SystemdCgroup = false|SystemdCgroup = true|' | tee /etc/containerd/config.toml > /dev/null 2>/dev/null
    if ! grep -q "SystemdCgroup = true" "/etc/containerd/config.toml"; then
        echo "Error: unable to set SystemdCgroup = true in /etc/containerd/config.toml file"
        exit 1
    fi
    systemctl restart containerd

    #Disable Firewall
    ufw disable

    #Disable swap
    swapoff -a; sed -i '/swap/d' /etc/fstab
    
    #Remove the tmp folder with all temporary files
    rm -rf /tmp/

    SetVariable "install_kubernetes_phase" 1
    echo "Install phase 0 is finished, please reboot and run this script again"
    exit 0
fi
#endregion

#region Install Phase 1
if [ $(GetVariable "install_kubernetes_phase" 0) = 1 ]; then
ReadYesNo "Is this a Master Node?"
IS_MASTER_NODE=$YES

if $IS_MASTER_NODE; then
echo 'Please select IPVS scheduling option: https://linux.die.net/man/8/ipvsadm'
echo '  disabled, rr: are good options for Game Server cluster'
echo '  sh: Source Hashing is required for Party cluster'

PS3='Please select IPVS scheduling option: '

select IPVS_SCHEDULER in $ALL_IPVS_OPTIONS
do
    if [[ " $ALL_IPVS_OPTIONS " = *" $IPVS_SCHEDULER "* ]]; then
        break
    fi
done
fi
echo "Starting install phase 1"
sudo apt-get -qq update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null 2>/dev/null
sudo apt-get -qq update -y
sudo apt-get install -y kubelet=$INSTALL_KUBE_VERSION kubeadm=$INSTALL_KUBE_VERSION kubectl=$INSTALL_KUBE_VERSION
sudo apt-mark hold kubelet kubeadm kubectl

if $IS_MASTER_NODE; then

cat > kubeadm.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $EXTERNAL_IP
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: $POD_NETWORK_CIDR
EOF

if [ $IPVS_SCHEDULER != "disabled" ]; then
    cat >> kubeadm.yaml <<EOF
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
ipvs:
  scheduler: $IPVS_SCHEDULER
EOF
fi
    #Initialize Kubernetes Cluster 
    kubeadm init --config kubeadm.yaml --ignore-preflight-errors=all --skip-token-print --skip-certificate-key-print
    
    export KUBECONFIG='/etc/kubernetes/admin.conf'

    # Deprecated, we assign scheduler option in kubeadm.yaml file, but this lines could be helpfull to modify the scheduler post install though     
    # if [ $IPVS_SCHEDULER != "disabled" ]; then
    #    kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s|scheduler: \"\"|scheduler: ${IPVS_SCHEDULER}|" | kubectl apply -f -
    #    kubectl delete pods -l k8s-app=kube-proxy -n kube-system
    # fi

    #Deploy Calico network
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v$INSTALL_CALICO_VERSION/manifests/tigera-operator.yaml
    curl -s https://raw.githubusercontent.com/projectcalico/calico/v$INSTALL_CALICO_VERSION/manifests/custom-resources.yaml | sed -e "s|192.168.0.0/16|${POD_NETWORK_CIDR}|" | kubectl create -f -

    #Remove the taints on the master so that you can schedule pods on it.
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>/dev/null
    kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null

    #Copy the config file to main folder
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    #Print the cluster join command
    kubeadm token create --print-join-command
else
    echo "You need to join the master node, run this command on master to get the token: kubeadm token create --print-join-command"
    # Follow the join instructions manually and then run the commands commented below
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane- > /dev/null 2>/dev/null
    # kubectl taint nodes --all node-role.kubernetes.io/master- > /dev/null 2>/dev/null
fi
echo "Install is finished"
SetVariable "install_kubernetes_phase" "FINISHED"
exit 0
fi
#endregion