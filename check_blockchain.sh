#!/bin/bash
current_height=$(curl -s https://api.helium.io/v1/blocks/height | jq .data.height)
miner_height=$(docker exec miner miner info height | awk '{print $2}')
height_diff=$(expr "$current_height" - "$miner_height")
percent_complete=$(expr 100 \* "$miner_height" / "$current_height")

echo "Blockchain Height: $current_height"
echo "Miner Height: $miner_height"
echo "Difference: $height_diff"
echo "Percent Complete: $percent_complete"
