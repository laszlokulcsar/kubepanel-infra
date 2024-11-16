#!/bin/bash
source .config_variable
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

    sed -i "s,<DJANGO_SUPERUSER_EMAIL>,$email,g" "$file"
    sed -i "s,<DJANGO_SUPERUSER_USERNAME>,$username,g" "$file"
    sed -i "s,<DJANGO_SUPERUSER_PASSWORD>,$password,g" "$file"
    sed -i "s,<KUBEPANEL_DOMAIN>,$domain,g" "$file"
    sed -i "s,<MARIADB_ROOT_PASSWORD>,$mariadbpass,g" "$file"
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
            echo "$(date): Deployment $DEPLOYMENT is not ready yet, it can take 5 to 10 minutes to complete."
        fi
        sleep 15
    done
}

main() {
    sudo apt update && sudo snap install microk8s --classic --channel=1.31
    echo "MicroK8S has been installed, waiting to be ready..."
    sudo microk8s status --wait-ready
    sudo microk8s enable hostpath-storage
    sudo microk8s enable ingress
    sudo microk8s enable cert-manager
    YAML_FILE="kubepanel-install.yaml"
    prompt_user_input "Enter Superuser email address: " DJANGO_SUPERUSER_EMAIL
    prompt_user_input "Enter Superuser username: " DJANGO_SUPERUSER_USERNAME
    prompt_user_input "Enter Superuser password: " DJANGO_SUPERUSER_PASSWORD
    prompt_user_input "Enter Kubepanel domain name: " KUBEPANEL_DOMAIN
    download_yaml "$GITHUB_URL" "$YAML_FILE"
    replace_placeholders "$YAML_FILE" "$DJANGO_SUPERUSER_EMAIL" "$DJANGO_SUPERUSER_USERNAME" "$DJANGO_SUPERUSER_PASSWORD" "$KUBEPANEL_DOMAIN"
    microk8s kubectl apply -f $YAML_FILE
    check_deployment_status
}
main
