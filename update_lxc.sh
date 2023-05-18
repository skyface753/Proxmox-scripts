#!/bin/bash

#Putty : enable "Implicit LF in every CR" to have fine screen reading

ct=$(pct list | awk '/^[0-9]/ {print $1}')
dt="$(date '+%d-%m-%Y_%H-%M-%S')"
log_file_global="general - $dt.log"
log_file_LXC=""
GREEN=$'\e[0;32m'
NC=$'\e[0m'

function log_general() {
    echo "${GREEN}$1${NC}"
    echo "$(date '+%d-%m-%Y_%H-%M-%S') - $1" >> "$log_file_global"
}

function log() {
    echo "${GREEN}$1${NC}"
    echo "$(date '+%d-%m-%Y_%H-%M-%S') - $1" >> "$log_file_LXC"
}

function execScreenLog () {
    eval $1 2>&1 | tee -a "$log_file_LXC"
}

function execLog() {
    eval $1 >> "$log_file_LXC"
}

function snapshotLXC () {
    log "Creating Snapshot for container: $container"
    # Ctrl of free space could be good
    execScreenLog "pct snapshot $container \"Update_$(date '+%Y%m%d_%H%M%S')\""
}

function aptUpgrade () {
    question "Create snapshot ?" "snapshotLXC $container" "log No snapshot created for container: $container"
    execScreenLog "pct exec $container -- bash -c \"apt -q upgrade -y\""
}

function question () {
    log "$1"
    select yn in "Yes" "No"; do
            case $yn in
                    Yes ) log "Yes"; $2; break;;
                    No ) log "No"; $3; break;;
            esac
    done
}

function statusLXC () {
        execScreenLog "pct status $container | grep -oP '(?<=status: ).*'"
}

function startLXC() {
        execScreenLog "pct start $1"
    #Should be changed.
    #Testing statuxLXC is not enough because LXC is "running" immediately (even if network is not working in the LXC)" ... for my LXC 5 seconds are enough for them to respond
    sleep 5
}

function aptUpdate () {
       execScreenLog "pct exec $container -- bash -c \"apt -q update\""
    execScreenLog "pct exec $container -- bash -c \"apt -q list --upgradable\""
}

function stopLXC () {
    execScreenLog "pct shutdown $container"
}

#Begining of the script
printf "\033c"
log_general "Script Start"

for container in $ct
do
    wasStopped=0
    log_general "Maintenance Start on container: $container"
    log_file_LXC="$container - $dt.log"
    log "Maintenance Start on container: $container"
    log "FsTrim on container: $container"
    execScreenLog "pct fstrim $container"
    case $(statusLXC $container) in
        "running") log "Container running: $container";;
        "stopped")
            question "Launch container: $container?" "startLXC $container" "log Container kept stopped: $container"
            wasStopped=1
            case $(statusLXC $container) in
                "stopped") printf "\033c"; continue;;
            esac;;
        *) log "Container $container unknown status"; continue;;
    esac
    #Find a way to count the line number and don't ask if there is no update pending
    aptUpdate
        question "Upgrade container: $container ?" "aptUpgrade" "log Container $container not updated"
    if [ "$wasStopped" = "1" ]
    then
        question "Stop back container : $container" "stopLXC $container" "log Container $container ketp running"
    fi
    #Find a way to ask for snapshot deletion ? Like update is made, you test your service while the script is waiting and then you ask for snapshot deletion
    log "Maintenance End on container: $container"
    log_general "Maintenance End on container: $container"
    read -p "Press any key to continue ..."
    printf "\033c"
done

log_general "Script finished"