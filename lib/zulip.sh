#!/usr/bin/env bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

function DEBUG () {
    [ "$_DEBUG" == "on" ] &&  "$@"
}

[ -n "${GOBCRON_ZULIP}" ] && return; GOBCRON_ZULIP=0; # pragma once

# send a message to our zulip chat; parameters: $1=receiver $2=message
zulipmessage () {
    local receiver="$1"
    local message="$2"
    curl -X POST https://goblint.zulipchat.com/api/v1/messages \
    -u "$(conf zulip.bot.email)":"$(conf zulip.bot.apikey)" \
    --data-urlencode type=direct \
    --data-urlencode "to=[$receiver]" \
    --data-urlencode "content=$message"
    DEBUG echo "zulipmessage to $receiver: $message"
}

# send a message to our zulip chat; parameters: $1=receiver $2=topic $3=message
zulipstream () {
    local streamname="$1"
    local topic="$2"
    local message="$3"
    curl -X POST https://goblint.zulipchat.com/api/v1/messages \
    -u "$(conf zulip.bot.email)":"$(conf zulip.bot.apikey)" \
    --data-urlencode type=stream \
    --data-urlencode "to=$streamname" \
    --data-urlencode "topic=$topic" \
    --data-urlencode "content=$message"
    DEBUG echo "zulipstream to $streamname: $message"
}

# message with zulipmessage "$ZULIP_MichaelP" "SV-Comp nightly script started." ;
# stream  with zulipstream  "tum-nightly-svcomp" "new run" "SV-Comp nightly script started." ;

