#!/bin/bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script via: \$ source $0" >&2
    exit 33
fi

[ -n "${GOBCRON_CONF}" ] && return; GOBCRON_CONF=0; # pragma once

function DEBUG () {
    [ "$_DEBUG" == "on" ] &&  "$@"
}

function initconf () {
    local base=$1
    if [ ! -f "$base"/conf/gobcron.user.json ] ; then touch "$base"/conf/gobcron.user.json ; echo "{ }" > "$base"/conf/gobcron.user.json ; fi
    GOBCRON_CONFIG=$(jq '.[0] * .[1]' -s <(sed 's#^\s*//.*##' "$base"/conf/gobcron.json) <(sed 's#^\s*//.*##' "$base"/conf/gobcron.user.json) | jq .)
    DEBUG echo "GOBCRON_CONFIG: $GOBCRON_CONFIG"
}

# update the config for this bash session (lifetime of variables)
function updateconf {
    local param=$1
    local value=$(cut -d "=" -f 2 <<< "$param")
    local key=$(cut -d "=" -f 1 <<< "$param")
    GOBCRON_CONFIG=$(jq ".$key=\"$value\"" <<< "$GOBCRON_CONFIG")
}

function updateconfigwithfile () {
    local file=$1
    GOBCRON_CONFIG=$(jq '.[0] * .[1]' -s <(echo "$GOBCRON_CONFIG") <(sed 's#^\s*//.*##' "$file") | jq .)

}

# conf echoes the query value $1=query
function conf () {
    [[ -z "$GOBCRON_CONFIG" ]] && echo "Error: GOBCRON_CONFIG is not initialized -- call initconf [basedir]" && return 1
    jq ."$1" <<< "$GOBCRON_CONFIG" | tr -d '"'
}

# conf echoes the query value $1=query
function confset () {
    [[ -z "$GOBCRON_CONFIG" ]] && echo "Error: GOBCRON_CONFIG is not initialized -- call initconf [basedir]" && return 1
    jq ."$1"' | if type=="array" then . else [.] end' <<< "$GOBCRON_CONFIG" 
}