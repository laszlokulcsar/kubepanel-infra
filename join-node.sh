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
    echo "║                      KUBEPANEL NODE JOINER                            ║"
    echo "║                   Add Node to Kubepanel Cluster                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                            ERROR                                      ║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║${NC} This script must be run as root or with sudo privileges          ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                                   ${RED}║${NC}"
        echo -e "${RED}║${NC} Please run:                                                       ${RED}║${NC}"
        echo -e "${RED}║${NC}   ${YELLOW}sudo su - ${NC}                                              ${RED}║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
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

prompt_user_input() {
    local prompt_message=$1
    local var_name=$2
    read -rp "$(printf "${YELLOW}==> %s: ${NC}" "$prompt_message")" $var_name
}

# Function to run commands with optional debug output
run_cmd() {
    if [ "$DEBUG_MODE" = "true" ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

run_cmd_critical() {
    if [ "$DEBUG_MODE" = "true" ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n  ${RED}✗${NC} Critical command failed with exit code $exit_code: $*"
        exit 1
    fi
    return 0
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

main() {
    print_header
    
    if [ "$DEBUG_MODE" = "true" ]; then
        echo -e "${YELLOW}🐛 Debug mode enabled - showing all command output${NC}\n"
    fi

    print_step "0" "Privilege Check"
    print_progress "Verifying root privileges..."
    check_root
    print_success "Running with root privileges"
    

    print_step "1" "System Preparation"
    print_progress "Stopping and disabling multipathd..."
    run_cmd sudo systemctl stop multipathd
    run_cmd sudo systemctl disable multipathd
    print_success "System services configured"
    
    print_step "2" "Package Installation"
    print_progress "Updating package repositories..."
    run_cmd sudo apt update
    print_progress "Installing LVM2..."
    run_cmd sudo apt install lvm2 -y
    print_success "Dependencies installed"
    
    print_progress "Installing MicroK8S (this may take a few minutes)..."
    run_cmd sudo snap install microk8s --classic --channel=1.31
    print_success "MicroK8S installed"
    
    print_step "3" "Storage Configuration"
    prompt_user_input "Enter storage device name [default: /dev/sdb]" STORAGE_DEVICE
    STORAGE_DEVICE=${STORAGE_DEVICE:-/dev/sdb}
    
    # Validate that the device exists
    if [ ! -b "$STORAGE_DEVICE" ]; then
        echo -e "  ${RED}✗${NC} Error: Device $STORAGE_DEVICE does not exist or is not a block device"
        echo -e "  ${YELLOW}Available block devices:${NC}"
        lsblk -d -o NAME,SIZE,TYPE | grep disk
        exit 1
    fi
    
    print_progress "Setting up LVM storage on $STORAGE_DEVICE..."
    
    # Check if VG already exists
    if vgs linstorvg >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC} Volume group 'linstorvg' already exists, skipping creation"
    else
        run_cmd_critical vgcreate linstorvg "$STORAGE_DEVICE"
    fi
    
    # Check if LV already exists
    if lvs linstorvg/linstorlv >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC} Logical volume 'linstorlv' already exists, skipping creation"
    else
        run_cmd_critical lvcreate -l100%FREE -T linstorvg/linstorlv
    fi
    print_success "Storage configured"
    
    print_step "4" "MicroK8S Initialization"
    print_waiting "Waiting for MicroK8S to be ready..."
    run_cmd sudo microk8s status --wait-ready
    print_success "MicroK8S is ready"
    
    # Final instructions
    echo -e "\n${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 NODE PREPARATION COMPLETED! 🎉                  ║"
    echo "║                 Get the join command from your main node              ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

main
