#!/bin/bash

# Script for auto updating the helium miner.

# Set default values
MINER=miner
REGION=US915
GWPORT=1680
MINERPORT=44158
DATADIR=/home/pi/miner_data

# Make sure we have the latest version of the script
function update-git {
   SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
   cd "$SCRIPT_DIR" && git pull
}

command -v jq > /dev/null || sudo apt-get install jq curl -y

# Read switches to override any default values for non-standard configs
while getopts n:g:p:d:r: flag
do
   case "${flag}" in
      n) MINER=${OPTARG};;
      g) GWPORT=${OPTARG};;
      p) MINERPORT=${OPTARG};;
      d) DATADIR=${OPTARG};;
      r) REGION=${OPTARG};;
      *) echo "Exiting"; exit;;
   esac
done

# Autodetect running image version and set arch
running_image=$(docker container inspect -f '{{.Config.Image}}' "$MINER" | awk -F: '{print $2}')
if [ -z "$running_image" ]; then
	ARCH=arm
elif [ "$(echo "$running_image" | awk -F_ '{print $1}')" == "miner-arm64" ]; then
	ARCH=arm
elif [ "$(echo "$running_image" | awk -F_ '{print $1}')" == "miner-amd64" ]; then 
	ARCH=amd
else
	ARCH=arm
	#below is just to make it not null.
	running_image=" "
fi

#miner_latest=$(curl -s 'https://quay.io/api/v1/repository/team-helium/miner/tag/?limit=100&page=1&onlyActiveTags=true' | jq -c --arg ARCH "$ARCH" '[ .tags[] | select( .name | contains($ARCH)) ][0].name' | cut -d'"' -f2)

miner_quay=$(curl -s 'https://quay.io/api/v1/repository/team-helium/miner/tag/?limit=100&page=1&onlyActiveTags=true' --write-out '\nHTTP_Response:%{http_code}')

miner_response=$(echo "$miner_quay" | grep "HTTP_Response" | cut -d":" -f2)

if [[ $miner_response -ne 200 ]];
	then
	echo "Bad Response from Server"
	exit 0
fi

miner_latest=$(echo "$miner_quay" | grep -v HTTP_Response | jq -c --arg ARCH "$ARCH" '[ .tags[] | select( .name | contains($ARCH)and contains("GA")) ][0].name' | cut -d'"' -f2)

echo "$(date)"
echo "$0 starting with MINER=$MINER GWPORT=$GWPORT MINERPORT=$MINERPORT DATADIR=$DATADIR REGION=$REGION"

#check to see if the miner is more than 50 block behind
current_height=$(curl -s https://api.helium.io/v1/blocks/height | jq .data.height) && sleep 2 ;miner_height=$(docker exec "$MINER" miner info height | awk '{print $2}');height_diff=$(expr "$current_height" - "$miner_height")

if [[ $height_diff -gt 50 ]]; then docker stop "$MINER" && docker start "$MINER" ; fi

#If the miner is more than 500 blocks behind, stop the image, remove the container, remove the image. It will be redownloaded later in the script.
if [[ $height_diff -gt 500 ]]; then docker stop "$MINER" && docker rm "$MINER" && docker image rm "$miner_latest" ; fi

if echo "$miner_latest" | grep -q $ARCH;
then echo "Latest miner version $miner_latest";
elif miner_latest=$(curl -s 'https://quay.io/api/v1/repository/team-helium/miner/tag/?limit=100&page=1&onlyActiveTags=true' | jq -r .tags[1].name)
then echo "Latest miner version $miner_latest";
fi

if [ "$miner_latest" = "$running_image" ];
then    echo "already on the latest version"
	update-git
        exit 0
fi

# Pull the new miner image. Downloading it now will minimize miner downtime after stop.
docker pull quay.io/team-helium/miner:"$miner_latest"

echo "Stopping and removing old miner"

docker stop "$MINER" && docker rm "$MINER"

echo "Deleting old miner software"

for image in $(docker images quay.io/team-helium/miner | grep "quay.io/team-helium/miner" | awk '{print $3}'); do
	image_cleanup=$(docker images | grep "$image" | awk '{print $2}')
	#change this to $running_image if you want to keep the last 2 images
	if [ "$image_cleanup" = "$miner_latest" ]; then
	       continue
        else
		echo "Cleaning up: $image_cleanup"
		docker image rm "$image"
        
        fi		
done

echo "Provisioning new miner version"

docker run -d --env REGION_OVERRIDE="$REGION" --restart always --publish "$GWPORT":"$GWPORT"/udp --publish "$MINERPORT":"$MINERPORT"/tcp --name "$MINER" --mount type=bind,source="$DATADIR",target=/var/data quay.io/team-helium/miner:"$miner_latest"

if [ "$GWPORT" -ne 1680 ] || [ "$MINERPORT" -ne 44158 ]; then
   echo "Using nonstandard ports, adjusting miner config"
   docker exec "$MINER" sed -i "s/44158/$MINERPORT/; s/1680/$GWPORT/" /opt/miner/releases/0.1.0/sys.config
   docker restart "$MINER"
fi
update-git
