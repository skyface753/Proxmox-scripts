#!/bin/bash

# list of container ids we need to iterate through
containers=$(pct list | tail -n +2 | cut -f1 -d' ')

EMAIL_MSG="Please see the log file attached.";
EMAIL_FROM="example@example.com";
EMAIL_TO="example@example.com";
DIRTOSCAN="/";

function virusscan() {
    container=$1
    echo "[Info] Scanning $container"
    # Container logfile
    LOGFILE="/var/log/clamav/clamav-$container-$(date +'%Y-%m-%d').log";
    ERRORLOGFILE="/var/log/clamav/clamav-$container-$(date +'%Y-%m-%d').error.log";
    echo Scansize: $(pct exec $container -- bash -c "du -sh $DIRTOSCAN 2>/dev/null | cut -f1")
    # check if clamav is installed with command -v
    if ! pct exec $container -- bash -c "command -v clamscan" &> /dev/null
    then
        echo "[Info] ClamAV is not installed on $container"
        installClamAV $container
    fi
    # Update ClamAV
    updateClamAV $container
    # Erros are not important
    pct exec $container -- bash -c "clamscan -ri $DIRTOSCAN" > "$LOGFILE" 2> "$ERRORLOGFILE";
    MALWARE=$(tail "$LOGFILE"|grep Infected|cut -d" " -f3);
    # Check if malware is not empty
    if [ -z "$MALWARE" ]; then
      # Throw error if malware is empty
      echo "[Error] Malware is empty"
      # Quit script
      exit 1
      MALWARE=0
    fi
    if [ "$MALWARE" -ne "0" ];then
        echo "The container $container is infected with $MALWARE" | mail -s "Virus detected on $container" -a "$LOGFILE" -r "$EMAIL_FROM" "$EMAIL_TO";
        echo "[Info] The container $container is infected with $MALWARE"
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

# Uninstall ClamAV
if [ "$1" == "uninstall" ]; then
  for container in $containers
  do
    echo "[Info] Uninstalling ClamAV on $container"
    pct exec $container -- bash -c "apt-get remove -y clamav clamav-freshclam clamav-daemon"
  done
  exit 0
fi


for container in $containers
do
  status=`pct status $container`
  if [ "$status" == "status: running" ]; then
      virusscan $container
  fi
done; wait
echo "[Info] Finished"  