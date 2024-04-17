#!/bin/bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

[ -n "${GOBCRON_CONF}" ] && return; GOBCRON_CONF=0; # pragma once

function initconf () {
    local base=$1
    if [ ! -f "$base"/conf/gobcron.user.json ] ; then touch "$base"/conf/gobcron.user.json ; fi
    GOBCRON_CONFIG=$(jq '.[0] * .[1]' -s <(json5 "$base"/conf/gobcron.json) <(json5 "$base"/conf/gobcron.user.json) | jq .)
}

# conf echoes the query value $1=query
function conf () {
    [[ -z "$GOBCRON_CONFIG" ]] && echo "Error: GOBCRON_CONFIG is not initialized -- call initconf [basedir]" && return 1
    jq ."$1" <<< "$GOBCRON_CONFIG" | sed -e 's/^"//' -e 's/"$//'
}