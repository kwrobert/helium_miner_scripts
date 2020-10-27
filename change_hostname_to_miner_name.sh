#/bin/bash

MINER="miner"
hostnamectl set-hostname $(docker exec $MINER miner info name)
