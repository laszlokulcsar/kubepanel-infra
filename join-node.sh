#!/bin/bash

sudo systemctl stop multipathd && sudo systemctl disable multipathd
vgcreate linstorvg /dev/sdb
lvcreate -l100%FREE -T linstorvg/linstorlv
sudo apt update && apt install lvm2 -y && sudo snap install microk8s --classic --channel=1.31
echo "MicroK8S has been installed, waiting to be ready..."
sudo microk8s status --wait-ready
echo "Please run the cluster join command:"
