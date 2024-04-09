#!/bin/bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# build the minimal gobcron.user.json
init () {
    local acc
    local value
    local confdir
    confdir=$(realpath "$SCRIPTDIR/../conf")
    if [[ -f "$confdir/gobcron.user.json" ]] ; then
        echo "$confdir/gobcron.user.json already exists, please remove it first"
        return 1
    fi
    acc=$(jq -n '.instance.basedir|="'$(realpath "$SCRIPTDIR/..")'"')
    acc=$(jq '.server.user|="'"$(whoami)"'"'<<< "$acc")
    acc=$(jq '.instance.tag|="'"$(whoami)"'"'<<< "$acc")
    value=$(host $(hostname) | head -n 1 | awk '{ print $1 }')
    acc=$(jq '.server.name|="'$value'"' <<< "$acc")
    value=$(($(lscpu | grep "^CPU(s):" | awk '{ print $2 }') - 1))
    acc=$(jq '.server.threads|="'$value'"' <<< "$acc")
    value=$(($(lsmem | grep "^Total online memory:" | awk '{ print $4 }' | head -c -2) / ($value + 1)))
    acc=$(jq '.server.memory|="'$value'G"' <<< "$acc")
    read -p "Enter the path to the SV-benchmark directory [enter defaults to $HOME/sv-benchmarks]: " value
    value=${value:-"$(realpath "$HOME/sv-benchmarks")"}
    acc=$(jq '.instance.svbenchdir|="'$value'"' <<< "$acc")
    value=$(jq '.zulip.user | keys | join(" ")' $confdir/gobcron.json | sed -e 's/^"//' -e 's/"$//')
    local PS3="Select the number of the user you want to message: "
    select uid in $value;
    do
        uid=$(jq '.zulip.user.'$uid $confdir/gobcron.json)
        acc=$(jq '.zulip.mode|='$uid <<< "$acc")
        break
    done
    echo "Now, let us connect to zulip, open https://zulip.com/help/add-a-bot-or-integration"
    read -p "Enter the zulip bot email: " value
    acc=$(jq '.zulip.bot.email|="'$value'"' <<< "$acc")
    read -p "Enter the zulip bot apikey: " value
    acc=$(jq '.zulip.bot.apikey|="'$value'"' <<< "$acc")
    echo "$acc" > $confdir/gobcron.user.json
    echo
    echo "Generated a new $confdir/gobcron.user.json"
}

init