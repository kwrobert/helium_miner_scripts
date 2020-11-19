#/bin/bash

MINER="miner"
current_hostname="$(hostname)"
new_hostname="$(docker exec $MINER miner info name)"
hostnamectl set-hostname $new_hostname
sed -i "s/$current_hostname/$new_hostname" /etc/hosts
