#!/bin/bash
set -euo pipefail

# Script for auto updating the helium miner.

function log {
  echo "$(date +%c): $*"
}
# Make sure we have the latest version of the script
function update-git {
   SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
   cd "$SCRIPT_DIR" && git pull
}

trim() {
  local var="$*"
  # remove leading whitespace characters
  var="${var#"${var%%[![:space:]]*}"}"
  # remove trailing whitespace characters
  var="${var%"${var##*[![:space:]]}"}"   
  printf '%s' "$var"
}

function get_cpu_arch {
  cpu_arch="$(lscpu | grep "Architecture" | tr -s " " | cut -d ":" -f 2)"
  cpu_arch="$(trim $cpu_arch)"
  log $cpu_arch
  if [[ "$cpu_arch" == "aarch64" ]]; then
    ARCH="arm"
  elif [[ "$cpu_arch" == "x86_64" ]]; then
    ARCH="amd"
  fi
}

function get_miner_image_json {
  log "Pulling list of images in JSON form"	
  miner_images_json=$(curl -s 'https://quay.io/api/v1/repository/team-helium/miner/tag/?limit=100&page=1&onlyActiveTags=true' --write-out '\nHTTP_Response:%{http_code}')
  miner_response=$(echo "$miner_images_json" | grep "HTTP_Response" | cut -d":" -f2)
  if [[ $miner_response -ne 200 ]]; then
    echo "Bad Response from Server"
    exit 0
  fi
}

function clean_old_images {
  for image in $(docker images quay.io/team-helium/miner | grep "quay.io/team-helium/miner" | awk '{print $3}'); do
    image_cleanup=$(docker images | grep "$image" | awk '{print $2}')
    #change this to $running_image if you want to keep the last 2 images
    if [ "$image_cleanup" = "$miner_latest" ]; then
      continue
    else
      log "Cleaning up: $image_cleanup"
      docker image rm "$image"
    fi		
  done
}

function run_docker_image {
  docker run -d --env REGION_OVERRIDE="$REGION" --restart always --publish "$GWPORT":"$GWPORT"/udp --publish "$MINERPORT":"$MINERPORT"/tcp --name "$MINER" --mount type=bind,source="$DATADIR",target=/var/data $1
}

echo "###################################"
log "BEGINNING SCRIPT RUN"

# Set default values
MINER=miner
REGION=US915
GWPORT=1680
MINERPORT=44158
DATADIR=/home/pi/miner_data
USE_DEV=false

log "Running with params: MINER=$MINER GWPORT=$GWPORT MINERPORT=$MINERPORT DATADIR=$DATADIR REGION=$REGION"

command -v jq > /dev/null || sudo apt-get install jq curl -y

# Read switches to override any default values for non-standard configs
while getopts n:g:p:d:r:l: flag
do
   case "${flag}" in
      n) MINER=${OPTARG};;
      g) GWPORT=${OPTARG};;
      p) MINERPORT=${OPTARG};;
      d) DATADIR=${OPTARG};;
      r) REGION=${OPTARG};;
      l) USE_DEV=false;;
      *) log "Exiting"; exit;;
   esac
done

# Autodetect running image version and set arch
get_cpu_arch
log "Running ARCH: $ARCH"

get_miner_image_json

if [ "$USE_DEV" = true ]; then
  miner_latest="latest-$ARCH64"
else
  miner_latest=$(echo "$miner_images_json" | grep -v HTTP_Response | jq -c --arg ARCH "$ARCH" '[ .tags[] | select( .name | contains($ARCH)and contains("GA")) ][0].name' | cut -d'"' -f2)
fi

log "Latest miner image: $miner_latest"
miner_latest_full_name="quay.io/team-helium/miner:$miner_latest"
# Pull the new miner image. Downloading it now will minimize miner downtime after stop.
log "Pulling latest miner image: $miner_latest_full_name"
docker pull $miner_latest_full_name	 

log "Getting running image"
running_image="$(docker ps --filter="name=$MINER" --format '{{.Image}}')"
log "Running image: $running_image"

if [[ -z "$running_image" ]]; then
  echo "No running miner, starting latest image"
  docker rm $MINER
  run_docker_image $miner_latest_full_name
  update-git
  exit 0
fi

if [[ "$miner_latest_full_name" != "$running_image" ]]; then
  log "Stopping and removing old miner"
  docker stop "$MINER" && docker rm "$MINER"
  log "Provisioning new miner version"
  run_docker_image $miner_latest_full_name
  if [ "$GWPORT" -ne 1680 ] || [ "$MINERPORT" -ne 44158 ]; then
     log "Using nonstandard ports, adjusting miner config"
     docker exec "$MINER" sed -i "s/44158/$MINERPORT/; s/1680/$GWPORT/" /opt/miner/releases/0.1.0/sys.config
     docker restart "$MINER"
  fi
  log "Deleting old miner software"
  clean_old_images
  update-git
  exit 0
fi

#check to see if the miner is more than 50 block behind
current_height=$(curl -s https://api.helium.io/v1/blocks/height | jq .data.height) && sleep 2
log "Current Blockchain Height: $current_height"
miner_height=$(docker exec "$MINER" miner info height | awk '{print $2}')
num_tries=0
while [[ -z "$miner_height" && num_tries -lt 3 ]]; do
  log "Retrying getting miner height"
  sleep 5
  miner_height=$(docker exec "$MINER" miner info height | awk '{print $2}')
  let "num_tries+=1" 
done

if [[ -z "$miner_height" ]]; then
  log "Unable to get miner height, exiting"
  exit 1
fi
 
log "Current Miner Height: $miner_height"
height_diff=$(expr "$current_height" - "$miner_height")
log "Difference: $height_diff"

if [[ $height_diff -gt 50 ]]; then
  log "Height diff greater than 50, restarting"
  docker restart $MINER
fi

#If the miner is more than 500 blocks behind, stop the image, remove the container, remove the image
if [[ $height_diff -gt 500 ]]; then
  log "Height diff greater than 500, cleaning container"
  docker stop "$MINER"
  docker rm "$MINER"
  log "Removing running miner image: $running_image"
  docker image rm "$running_image"
  docker pull $miner_latest_full_name
  run_docker_image $miner_latest_full_name
fi

update-git
