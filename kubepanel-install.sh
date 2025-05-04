#!/bin/bash

if [ "$1" == "dev" ]; then
    GITHUB_URL="https://raw.githubusercontent.com/laszlokulcsar/kubepanel-infra/refs/heads/v0.2/kubepanel-install.yaml"
else
    GITHUB_URL="https://raw.githubusercontent.com/laszlokulcsar/kubepanel-infra/refs/heads/main/kubepanel-install.yaml"
fi

prompt_user_input() {
    local prompt_message=$1
    local var_name=$2
    read -p "$prompt_message: " $var_name
}

download_yaml() {
    local url=$1
    local output_file=$2
    curl -o "$output_file" "$url"

    if [ $? -ne 0 ]; then
        echo "Failed to download the file from $url."
        exit 1
    fi
}

replace_placeholders() {
    local file=$1
    local email=$2
    local username=$3
    local password=$4
    local domain=$5
    local mariadbpass=$(openssl rand -base64 15)
    local mariadbpass_rc=$(openssl rand -base64 15)

    mapfile -t node_ips < <(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | head -n 3)
    local node1_ip=${node_ips[0]}
    local node2_ip=${node_ips[1]}
    local node3_ip=${node_ips[2]}

    sed -i "s,<DJANGO_SUPERUSER_EMAIL>,$email,g" "$file"
    sed -i "s,<DJANGO_SUPERUSER_USERNAME>,$username,g" "$file"
    sed -i "s,<DJANGO_SUPERUSER_PASSWORD>,$password,g" "$file"
    sed -i "s,<KUBEPANEL_DOMAIN>,$domain,g" "$file"
    sed -i "s,<MARIADB_ROOT_PASSWORD>,$mariadbpass,g" "$file"
    sed -i "s,<MARIADB_ROOT_PASSWORD_RC>,$mariadbpass_rc,g" "$file"
    sed -i "s,<NODE_1_IP>,$node1_ip,g" "$file"
    sed -i "s,<NODE_2_IP>,$node2_ip,g" "$file"
    sed -i "s,<NODE_3_IP>,$node3_ip,g" "$file"
}

check_deployment_status() {
    DEPLOYMENT="kubepanel"
    NAMESPACE="kubepanel"
    while true; do
        STATUS=$(microk8s kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
        if [ "$STATUS" == "True" ]; then
            echo "$(date): Deployment $DEPLOYMENT is ready."
            break
        else
            echo "$(date): Deployment $DEPLOYMENT is not ready yet, it can take 15 to 20 minutes to complete."
        fi
        sleep 15
    done
}

generate_join_command() {
    echo "Generating join command..."
    # Generate a token with a longer TTL (e.g., 1 hour) so multiple nodes can join using the same token
    JOIN_COMMAND=$(microk8s add-node --token-ttl 3600)
    echo "Please run the following command(s) on the other nodes to join them to the cluster:"
    echo "$JOIN_COMMAND"
}

wait_for_ha_status() {
    echo "Waiting for the cluster to achieve high availability..."
    while true; do
        HA_STATUS=$(microk8s status | grep 'high-availability' | awk '{print $2}')
        if [ "$HA_STATUS" == "yes" ]; then
            echo "$(date): High Availability is enabled."
            break
        else
            echo "$(date): High Availability is not yet enabled. Waiting for nodes to join..."
        fi
        sleep 15
    done
}

main() {
    sudo systemctl stop multipathd && sudo systemctl disable multipathd
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /bin
    sudo apt update && apt install git lvm2 -y && sudo snap install microk8s --classic --channel=1.31
    echo "MicroK8S has been installed, waiting to be ready..."
    sudo microk8s status --wait-ready
    sudo microk8s enable ingress
    sudo microk8s enable cert-manager
    sudo microk8s config > .kube/config

    generate_join_command
    wait_for_ha_status
    vgcreate linstorvg /dev/sdb
    lvcreate -l100%FREE -T linstorvg/linstorlv
    kubectl apply --server-side -k "https://github.com/piraeusdatastore/piraeus-operator//config/default?ref=v2.7.0"
    kubectl apply -k https://github.com/kubernetes-csi/external-snapshotter//client/config/crd
    kubectl apply -k https://github.com/kubernetes-csi/external-snapshotter//deploy/kubernetes/snapshot-controller
    YAML_FILE="kubepanel-install.yaml"
    prompt_user_input "Enter Superuser email address" DJANGO_SUPERUSER_EMAIL
    prompt_user_input "Enter Superuser username" DJANGO_SUPERUSER_USERNAME
    prompt_user_input "Enter Superuser password" DJANGO_SUPERUSER_PASSWORD
    prompt_user_input "Enter Kubepanel domain name" KUBEPANEL_DOMAIN
    download_yaml "$GITHUB_URL" "$YAML_FILE"
    replace_placeholders "$YAML_FILE" "$DJANGO_SUPERUSER_EMAIL" "$DJANGO_SUPERUSER_USERNAME" "$DJANGO_SUPERUSER_PASSWORD" "$KUBEPANEL_DOMAIN"
    kubectl wait pod --for=condition=Ready --timeout=180s -n piraeus-datastore -l app.kubernetes.io/component=piraeus-operator
    kubectl apply -f $YAML_FILE
    check_deployment_status
    echo "Software Defined Storage component has been installed, waiting to be ready... It can take up to 10-15 minutes..."
    kubectl delete daemonset node-ip-updater -n kubepanel
}
main

