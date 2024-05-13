#!/bin/bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"


printf "checking programs... "
list="jq awk curl date sed git make xargs benchexec"
for prog in $list; do
  command -v $prog >/dev/null 2>&1 && continue || echo -e "\E[31m\033[1m program $prog required but not installed\033[0m"
  exit 1
done
echo -e '\E[32m'"\033[1m[ok]\033[0m"


printf "checking libraries... "
list="gcc-multilib"
for lib in $list; do
  dpkg -s "$lib" 2>/dev/null 1>/dev/null && continue || echo -e "\E[31m\033[1m library $lib required but not installed\033[0m"
  exit 1
done
echo -e '\E[32m'"\033[1m[ok]\033[0m"

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
    acc=$(jq '.server.memory|="'$value'GB"' <<< "$acc")
    read -p "Enter the path to the SV-benchmark directory [enter defaults to $HOME/sv-benchmarks]: " value
    value=${value:-"$(realpath "$HOME/sv-benchmarks")"}
    acc=$(jq '.instance.svbenchdir|="'$value'"' <<< "$acc")
    value=$(jq '.zulip.user | keys | join(" ")' <(sed 's#^\s*//.*##' $confdir/gobcron.json) | sed -e 's/^"//' -e 's/"$//')
    local PS3="Select the number of the user you want to message: "
    select uid in $value;
    do
        uid=$(jq '.zulip.user.'$uid <(sed 's#^\s*//.*##' $confdir/gobcron.json))
        acc=$(jq '.zulip.mode|='$uid <<< "$acc")
        break
    done
    printf '\e]8;;https://goblint.zulipchat.com/#settings/your-bots\e\\Now open Your Zulip bot settings\e]8;;\e\\\n'
    read -p "Enter the zulip bot email: " value
    acc=$(jq '.zulip.bot.email|="'$value'"' <<< "$acc")
    read -p "Enter the zulip bot apikey: " value
    acc=$(jq '.zulip.bot.apikey|="'$value'"' <<< "$acc")
    echo "$acc" > $confdir/gobcron.user.json
    echo
    echo "Generated a new $confdir/gobcron.user.json"
}

init
