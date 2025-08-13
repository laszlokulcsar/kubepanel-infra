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
    echo "║                      KUBEPANEL NODE JOINER                           ║"
    echo "║                   Add Node to Kubepanel Cluster                     ║"
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
    print_progress "Creating LVM volume group..."
    run_cmd vgcreate linstorvg /dev/sdb
    print_progress "Creating logical volume..."
    run_cmd lvcreate -l100%FREE -T linstorvg/linstorlv
    print_success "Storage configured"
    
    print_step "4" "MicroK8S Initialization"
    print_waiting "Waiting for MicroK8S to be ready..."
    run_cmd sudo microk8s status --wait-ready
    print_success "MicroK8S is ready"
    
    # Final instructions
    echo -e "\n${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    🎉 NODE PREPARATION COMPLETED! 🎉                  ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                           NEXT STEP                                ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${YELLOW}1. Get the join command from your main node:${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}This node is now ready to join your Kubepanel cluster!${NC}\n"
}

main
