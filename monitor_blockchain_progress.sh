#!/bin/bash

function get_blockchain_progress () {
  current_height=$(curl -s https://api.helium.io/v1/blocks/height | jq .data.height)
  miner_height=$(docker exec miner miner info height | awk '{print $2}')
  height_diff=$(expr "$current_height" - "$miner_height")
  percent_complete=$(expr 100 \* "$miner_height" / "$current_height")
  
  echo "Blockchain Height: $current_height"
  echo "Miner Height: $miner_height"
  echo "Difference: $height_diff"
  echo "Percent Complete: $percent_complete"
}



while true; do

  echo "-------------------------------"
  get_blockchain_progress
  
  # Make sure CSV file has header
  if [ ! -f "/home/pi/miner_data/block_times.txt" ]; then
    echo "#datetime,miner_height,blockchain_height" > /home/pi/miner_data/block_times.txt
  fi
  
  datetime=$(date +%D_%T)
  echo "$datetime,$miner_height,$current_height" >> /home/pi/miner_data/block_times.txt
	
  # Be nice to the helium API
  sleep $(shuf -i 5-30 -n 1)
done 
