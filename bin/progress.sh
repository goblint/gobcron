#!/bin/bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

function drawbar {
    dd if=/dev/urandom count="$1" bs=1 2> /dev/null | pv -f -p -w 70 -s 100 > /dev/null
}

# main function
function main {

    basedir="$(conf "instance.basedir")"
    cd "$basedir"

    local currentfile; currentfile=$(ls "$basedir/$(conf "instance.resultsdir")/current/"*.results.txt )
    local oldfile;         oldfile=$(ls "$basedir/$(conf "instance.resultsdir")/old.1/"*.results.txt)

    local files; files=$(grep -oP '^Statistics:\s+\d+\s+Files' "$oldfile")
    files=$(echo "$files" | grep -oP '\d+')
    local sofar; sofar=$(grep -c 'yml' "$currentfile")
    local progress; progress=$(echo "$sofar * 100 / $files " | bc)
    

    flock -n -x /tmp/gobcron.flock true || echo "currently, lock /tmp/gobcron.flock is taken by process with PID $(cat /tmp/gobcron.flock)"
    local gobpid; gobpid=$(cat /tmp/gobcron.flock)
    local gobbase; gobbase=$(ps -eadf | grep benchexec | grep "$gobpid"| tr -s ' '| rev | cut -f 1 -d " " | rev | xargs dirname)    
    local gobtag; gobtag=$(cat "$gobbase/results/current/tag")

    echo "$progress% progressed for tag $gobtag from $gobbase"
    drawbar "$progress"
}

main