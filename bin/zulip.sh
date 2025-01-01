#!/bin/bash
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

basedir="$(conf "instance.basedir")"
cd "$basedir"


#test if there is no argument
if [ -z "$1" ]; then
    json5 conf/gobcron.json | jq .zulip.user
    echo "bin/zulip.sh [ID] \"your message\""
    echo "  with [ID] being either the numeric user ID or the textual name of the user"
    cd -
    exit 0
fi

#test if there is a second argument
if [ -z "$2" ]; then
    zulipmessage 652581 "$1"
    cd -
    exit 0
fi

#test if argument 1 is purely numeric
if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    query=$(json5 conf/gobcron.json | jq .zulip.user."$1")
    
    #test if query is literally null
    if [ "$query" == "null" ]; then
        echo "User not found"
        cd -
        exit 1
    fi

    #trim first and last character from query
    query=${query:1:${#query}-2}

    echo "$query"

    zulipmessage "$query" "$2"
    cd -
    exit 0
fi

zulipmessage "$1" "$2"
cd -
exit 0