#!/bin/bash

# list of container ids we need to iterate through
containers=$(pct list | tail -n +2 | cut -f1 -d' ')

EMAIL_MSG="Please see the log file attached.";
EMAIL_FROM="example@example.com";
EMAIL_TO="example@example.com";
DIRTOSCAN="/";
LOGFOLDERROOT="/var/log/clamav";
LOGFOLDER="$LOGFOLDERROOT/$(date +'%Y-%m-%d')";
DISCORD_URL=


# Create log folder if not exists
if [ ! -d "$LOGFOLDER" ]; then
  mkdir -p "$LOGFOLDER"
fi

generate_discord_post_data() {
  # discord url empty
  if [ -z "$DISCORD_URL" ]; then
    return
  fi
  # yellow
  COLOR="16776960"
  # color based on $1 as true or false
  if [ "$1" = "true" ]; then
    COLOR="16711680"
  fi
  cat <<EOF
{
  "content": "ClamAV scan result",
  "embeds": [{
    "title": "$2",  
    "description": "$3",
    "color": "$COLOR"
  }]
}
EOF
}

function virusscan() {
    container=$1
    echo "[Info] Container $container"
    # Container logfile
    LOGFILE="$LOGFOLDER/clamav-$container.log";
    ERRORLOGFILE="$LOGFOLDER/clamav-$container.error.log";
    echo "[Info] Scansize: $(pct exec $container -- bash -c "du -sh $DIRTOSCAN 2>/dev/null | cut -f1")"
    # check if clamav is installed with command -v
    if ! pct exec $container -- bash -c "command -v clamscan" &> /dev/null
    then
        echo "[Info] ClamAV is not installed on $container"
        installClamAV $container
    fi
    # Update ClamAV
    updateClamAV $container
    # Scan container
    echo "[Info] Scanning $container"
    # Erros are not important (e.g. permission denied)
    pct exec $container -- bash -c "clamscan -ri $DIRTOSCAN" > "$LOGFILE" 2> "$ERRORLOGFILE";
    MALWARE=$(tail "$LOGFILE"|grep Infected|cut -d" " -f3);
    # Check if malware is not empty
    if [ -z "$MALWARE" ]; then
      # Throw error if malware is empty
      echo "[Error] Malware is empty"
      echo "Logfile of $container empty" | mail -s "Please check $container" -r "$EMAIL_FROM" "$EMAIL_TO";
      # Send message to discord
      curl -H "Content-Type: application/json" -X POST -d "$(generate_discord_post_data false "Please check $container" "Logfile of $container empty")" $DISCORD_URL
      # Quit script
      exit 1
      MALWARE=0
    fi
    if [ "$MALWARE" -ne "0" ];then
        echo "The container $container is infected with $MALWARE" | mail -s "Virus detected on $container" -a "$LOGFILE" -r "$EMAIL_FROM" "$EMAIL_TO";
        echo "[WARN] The container $container is infected with $MALWARE"
        # Send message to discord
        curl -H "Content-Type: application/json" -X POST -d "$(generate_discord_post_data true "Virus detected on $container" "The container $container is infected with $MALWARE")" $DISCORD_URL
    fi
}

function installClamAV() {
    container=$1
    echo "[Info] Installing ClamAV on $container"
    # No output
    pct exec $container -- bash -c "apt-get update && apt-get install -y clamav clamav-freshclam" > /dev/null
}

function updateClamAV() {
    container=$1
    echo "[Info] Updating ClamAV on $container"
    # No output and no error
    pct exec $container -- bash -c "freshclam" > /dev/null 2>&1
}

for container in $containers
do
  status=`pct status $container`
  if [ "$status" == "status: running" ]; then
      virusscan $container
  fi
done; wait
echo "[Info] Finished"