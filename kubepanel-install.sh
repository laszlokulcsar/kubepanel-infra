#!/bin/bash

# ──────────────── Colours ────────────────
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m' # No Colour

# Debug mode - check if KUBEPANEL_DEBUG is set to "true"
DEBUG_MODE=${KUBEPANEL_DEBUG:-false}

# ASCII Art and Progress Functions
print_header() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                         KUBEPANEL INSTALLER                           ║"
    echo "║              Kubernetes based web hosting control panel               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    local step_num=$1
    local step_name=$2
    echo -e "\n${BLUE}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${YELLOW}Step $step_num:${NC} $step_name"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

print_progress() {
    local message=$1
    echo -e "  ${GREEN}▶${NC} $message"
}

print_waiting() {
    local message=$1
    echo -e "  ${YELLOW}⏳${NC} $message"
}

print_success() {
    local message=$1
    echo -e "  ${GREEN}✓${NC} $message"
}

print_spinner() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r  ${YELLOW}${spin:$i:1}${NC} $message"
        sleep .1
    done
    printf "\r  ${GREEN}✓${NC} $message\n"
}

# Function to run commands with optional debug output
run_cmd() {
    if [ "$DEBUG_MODE" = "true" ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# Function to run commands and capture exit status while hiding output
run_cmd_check() {
    if [ "$DEBUG_MODE" = "true" ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
    return $?
}

if [ "$1" == "dev" ]; then
    GITHUB_URL="https://raw.githubusercontent.com/laszlokulcsar/kubepanel-infra/refs/heads/v0.2/kubepanel-install.yaml"
else
    GITHUB_URL="https://raw.githubusercontent.com/laszlokulcsar/kubepanel-infra/refs/heads/main/kubepanel-install.yaml"
fi

prompt_user_input() {
    local prompt_message=$1
    local var_name=$2
    read -rp "$(printf "${YELLOW}==> %s: ${NC}" "$prompt_message")" $var_name
}

download_yaml() {
    local url=$1
    local output_file=$2
    run_cmd_check curl -o "$output_file" "$url"

    if [ $? -ne 0 ]; then
        echo "Failed to download the file from $url."
        exit 1
    fi
}

get_external_ips() {
    # Wait a moment for ConfigMap to be populated
    sleep 5
    
    # Get external IPs from ConfigMap
    EXTERNAL_IPS=()
    if [ "$DEBUG_MODE" = "true" ]; then
        mapfile -t EXTERNAL_IPS < <(microk8s kubectl get configmap node-public-ips -n kubepanel -o jsonpath='{.data}' | grep -oE '"[^"]+":"[^"]+"' | sed 's/"//g' | sed 's/:/: /')
    else
        mapfile -t EXTERNAL_IPS < <(microk8s kubectl get configmap node-public-ips -n kubepanel -o jsonpath='{.data}' 2>/dev/null | grep -oE '"[^"]+":"[^"]+"' | sed 's/"//g' | sed 's/:/: /')
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

    echo "Waiting for 3 nodes to report InternalIP…"
    while true; do
      sleep 5
      if [ "$DEBUG_MODE" = "true" ]; then
          mapfile -t node_ips < <(microk8s kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | head -n 3)
      else
          mapfile -t node_ips < <(microk8s kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | head -n 3)
      fi
      if [[ -n "${node_ips[0]}" && -n "${node_ips[1]}" && -n "${node_ips[2]}" ]]; then
        break
      fi
      echo "  still waiting…"
    done
    local node1_ip=${node_ips[0]}
    local node2_ip=${node_ips[1]}
    local node3_ip=${node_ips[2]}

    run_cmd sed -i "s,<DJANGO_SUPERUSER_EMAIL>,$email,g" "$file"
    run_cmd sed -i "s,<DJANGO_SUPERUSER_USERNAME>,$username,g" "$file"
    run_cmd sed -i "s,<DJANGO_SUPERUSER_PASSWORD>,$password,g" "$file"
    run_cmd sed -i "s,<KUBEPANEL_DOMAIN>,$domain,g" "$file"
    run_cmd sed -i "s,<MARIADB_ROOT_PASSWORD>,$mariadbpass,g" "$file"
    run_cmd sed -i "s,<MARIADB_ROOT_PASSWORD_RC>,$mariadbpass_rc,g" "$file"
    run_cmd sed -i "s,<NODE_1_IP>,$node1_ip,g" "$file"
    run_cmd sed -i "s,<NODE_2_IP>,$node2_ip,g" "$file"
    run_cmd sed -i "s,<NODE_3_IP>,$node3_ip,g" "$file"
}

check_deployment_status() {
    DEPLOYMENT="kubepanel"
    NAMESPACE="kubepanel"
    print_waiting "Waiting for Kubepanel deployment to be ready (15-20 minutes)..."
    while true; do
        if [ "$DEBUG_MODE" = "true" ]; then
            STATUS=$(microk8s kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
        else
            STATUS=$(microk8s kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
        fi
        if [ "$STATUS" == "True" ]; then
            print_success "Deployment $DEPLOYMENT is ready"
            break
        else
            echo -e "    ${YELLOW}⏳${NC} $(date): Deployment still starting up..."
        fi
        sleep 15
    done
}

generate_join_command() {
    print_progress "Generating cluster join command..."
    # Generate a token with a longer TTL (e.g., 1 hour) so multiple nodes can join using the same token
    if [ "$DEBUG_MODE" = "true" ]; then
        JOIN_COMMAND=$(microk8s add-node --token-ttl 3600 | head -n 2)
    else
        JOIN_COMMAND=$(microk8s add-node --token-ttl 3600 2>/dev/null | head -n 2)
    fi
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                     CLUSTER JOIN COMMAND                          ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC} ${YELLOW}%s${NC}\n" "$JOIN_COMMAND"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
}

wait_for_ha_status() {
    print_waiting "Waiting for the cluster to achieve high availability..."
    while true; do
        if [ "$DEBUG_MODE" = "true" ]; then
            HA_STATUS=$(microk8s status | grep 'high-availability' | awk '{print $2}')
        else
            HA_STATUS=$(microk8s status 2>/dev/null | grep 'high-availability' | awk '{print $2}')
        fi
        if [ "$HA_STATUS" == "yes" ]; then
            print_success "High Availability is enabled"
            break
        else
            echo -e "    ${YELLOW}⏳${NC} $(date): Waiting for additional nodes to join..."
        fi
        sleep 15
    done
}

main() {
    print_header
    
    if [ "$DEBUG_MODE" = "true" ]; then
        echo -e "${YELLOW}🐛 Debug mode enabled - showing all command output${NC}\n"
    fi
    
    print_step "1" "System Preparation"
    print_progress "Stopping and disabling multipathd..."
    run_cmd sudo systemctl stop multipathd
    run_cmd sudo systemctl disable multipathd
    print_success "System services configured"
    
    print_progress "Downloading kubectl..."
    run_cmd_check curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    run_cmd chmod +x kubectl
    run_cmd sudo mv kubectl /bin
    print_success "kubectl installed"
    
    print_step "2" "Package Installation"
    print_progress "Updating package repositories..."
    run_cmd sudo apt update
    print_progress "Installing dependencies (git, lvm2)..."
    run_cmd sudo apt install git lvm2 -y
    print_success "Dependencies installed"
    
    print_step "3" "MicroK8S Installation"
    print_progress "Installing MicroK8S (this may take a few minutes)..."
    run_cmd sudo snap install microk8s --classic --channel=1.31
    print_success "MicroK8S installed"
    
    print_waiting "Waiting for MicroK8S to be ready..."
    run_cmd sudo microk8s status --wait-ready
    print_success "MicroK8S is ready"
    
    print_step "4" "Kubernetes Configuration"
    print_progress "Enabling ingress addon..."
    run_cmd sudo microk8s enable ingress
    print_progress "Enabling cert-manager addon..."
    run_cmd sudo microk8s enable cert-manager
    print_progress "Configuring kubectl access..."
    run_cmd sudo microk8s config > .kube/config
    print_success "Kubernetes addons enabled"

    print_step "5" "High Availability Setup"
    generate_join_command
    wait_for_ha_status
    
    print_step "6" "Storage Configuration"
    print_progress "Setting up LVM storage..."
    run_cmd vgcreate linstorvg /dev/sdb
    run_cmd lvcreate -l100%FREE -T linstorvg/linstorlv
    print_success "Storage configured"
    
    print_step "7" "Kubernetes Operators"
    print_progress "Installing Piraeus storage operator..."
    run_cmd microk8s kubectl apply --server-side -k "https://github.com/piraeusdatastore/piraeus-operator//config/default?ref=v2.9.0"
    print_progress "Installing snapshot controller..."
    run_cmd microk8s kubectl apply -k https://github.com/kubernetes-csi/external-snapshotter//client/config/crd
    run_cmd microk8s kubectl apply -k https://github.com/kubernetes-csi/external-snapshotter//deploy/kubernetes/snapshot-controller
    print_success "Kubernetes operators installed"
    
    print_step "8" "Kubepanel Configuration"
    echo -e "\n${CYAN}Please provide the following configuration details:${NC}"
    YAML_FILE="kubepanel-install.yaml"
    prompt_user_input "Enter Superuser email address" DJANGO_SUPERUSER_EMAIL
    prompt_user_input "Enter Superuser username" DJANGO_SUPERUSER_USERNAME
    prompt_user_input "Enter Superuser password" DJANGO_SUPERUSER_PASSWORD
    prompt_user_input "Enter Kubepanel domain name" KUBEPANEL_DOMAIN
    
    print_progress "Downloading Kubepanel configuration..."
    download_yaml "$GITHUB_URL" "$YAML_FILE"
    print_progress "Customizing configuration..."
    replace_placeholders "$YAML_FILE" "$DJANGO_SUPERUSER_EMAIL" "$DJANGO_SUPERUSER_USERNAME" "$DJANGO_SUPERUSER_PASSWORD" "$KUBEPANEL_DOMAIN"
    print_success "Configuration prepared"
    
    print_step "9" "Deployment"
    print_waiting "Waiting for Piraeus operator to be ready (up to 3 minutes)..."
    run_cmd microk8s kubectl wait pod --for=condition=Ready --timeout=180s -n piraeus-datastore -l app.kubernetes.io/component=piraeus-operator
    print_success "Piraeus operator ready"
    
    print_progress "Deploying Kubepanel..."
    run_cmd microk8s kubectl apply -f $YAML_FILE
    
    check_deployment_status
    
    print_waiting "Finalizing storage setup (10-15 minutes)..."
    run_cmd microk8s kubectl delete daemonset node-ip-updater -n kubepanel
    
    print_progress "Retrieving external IP addresses..."
    get_external_ips
    
    # Final success message with DNS instructions
    echo -e "\n${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 INSTALLATION COMPLETED! 🎉                     ║"
    echo "║                                                                       ║"
    echo "║  Kubepanel is now ready to use at: https://$KUBEPANEL_DOMAIN"
    printf "%-71s║\n" "║  Login with your configured credentials"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Display node IPs and DNS instructions
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                          DNS CONFIGURATION                        ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${YELLOW}Internal Node IPs:${NC}"
    for i in "${!CLUSTER_NODE_IPS[@]}"; do
        printf "${BLUE}║${NC}   Node $((i+1)): ${GREEN}%-52s${NC}${BLUE}║${NC}\n" "${CLUSTER_NODE_IPS[i]}"
    done
    echo -e "${BLUE}║${NC}"
    
    # Display external IPs if available
    if [ ${#EXTERNAL_IPS[@]} -gt 0 ]; then
        echo -e "${BLUE}║${NC} ${YELLOW}External Node IPs:${NC}"
        for ip_mapping in "${EXTERNAL_IPS[@]}"; do
            printf "${BLUE}║${NC}   ${GREEN}%-60s${NC}${BLUE}║${NC}\n" "$ip_mapping"
        done
        echo -e "${BLUE}║${NC}"
        echo -e "${BLUE}║${NC} ${YELLOW}DNS Setup Required:${NC}"
        echo -e "${BLUE}║${NC}   Create an A record for: ${GREEN}$KUBEPANEL_DOMAIN${NC}"
        echo -e "${BLUE}║${NC}   Point it to one of the ${YELLOW}EXTERNAL${NC} IP addresses above"
    else
        echo -e "${BLUE}║${NC} ${YELLOW}DNS Setup Required:${NC}"
        echo -e "${BLUE}║${NC}   Create an A record for: ${GREEN}$KUBEPANEL_DOMAIN${NC}"
        echo -e "${BLUE}║${NC}   Point it to at least one of the internal IP addresses above"
        echo -e "${BLUE}║${NC}   ${YELLOW}Note:${NC} External IPs not yet available in ConfigMap"
    fi
    
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${RED}⚠️  Important:${NC} Kubepanel will not be accessible until"
    echo -e "${BLUE}║${NC}   the DNS record is configured correctly!"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}Please configure your DNS and then access Kubepanel at:${NC}"
    echo -e "${GREEN}https://$KUBEPANEL_DOMAIN${NC}\n"
}

main
