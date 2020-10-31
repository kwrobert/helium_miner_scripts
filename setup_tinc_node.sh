#!/bin/bash

TOKEN="$1"
BOOTNODE_ADDRESS="$2"

if [[ "$TOKEN" -eq "" ]]; then
    echo "Must specify authentication token for boot node API as first arg"
    exit 1
fi

if [[ "$BOOTNODE_IP" -eq "" ]]; then
    echo "Must specify public IP of boot node as second arg. Ex: http(s)://$PUBLIC_BOOTNODE_IP:$BOOTNODE_API_PORT"
    exit 1
fi

ARCH=$(lscpu | grep Architecture | tr -s " " | cut -d " " -f 2)

if [[ "$ARCH" -eq "aarch64" ]]; then
    wget -O tinc-boot_linux.deb https://github.com/reddec/tinc-boot/releases/download/v0.0.7/tinc-boot_linux_arm64.deb
elif [[ "$ARCH" -eq "x86_86" ]]; then
    wget -O tinc-boot_linux.deb https://github.com/reddec/tinc-boot/releases/download/v0.0.7/tinc-boot_linux_amd64.deb
else
    echo "Need to add if branch in script for CPU architecture: $ARCH"
    exit 1
fi

sudo apt install -y ./tinc-boot_linux.deb
sudo tinc-boot gen --token="$TOKEN" $BOOTNODE_ADDRESS
sudo systemctl enable tinc@dnet
sudo systemctl start tinc@dnet
