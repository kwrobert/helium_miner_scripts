#!/bin/bash

DATADIR="$HOME/miner_data/"

# DATADIR is bind mounted to /var/data within the container
snapshot_name="ledger_snapshot_$(date +%m-%d-%Y_%Mh%Hm%Ss).bin"
docker exec miner miner snapshot take /var/data/$snapshot_name
#docker cp /var/data/$snapshot_name ~/

echo "Snapshot saved to $DATADIR/$snapshot_name"
