#!/bin/bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

function drawbar {
    echo -ne "\r"
    dd if=/dev/urandom count="$1" bs=1 2> /dev/null | pv -f -p -w 100 -s 100 -X 2>&1
}

# main function
function main {

    basedir="$(conf "instance.basedir")"
    cd "$basedir"

    local currentfile; currentfile=0
    local sofar;  sofar=0

    if [ ! -d "$basedir/$(conf "instance.resultsdir")/old.1" ]; then
        echo "no former run present in ..../current, so we assume that analysis has not started yet"
    else
        currentfile=$(ls "$basedir/$(conf "instance.resultsdir")/current/"*.results.txt )
        sofar=$(grep -c 'yml' "$currentfile")
    fi

    local files; files=33000
    if [ ! -d "$basedir/$(conf "instance.resultsdir")/old.1" ]; then
        echo "no former run present in ..../current, so we assume a maximum of $files files" 
    else
        local oldfile;         oldfile=$(ls "$basedir/$(conf "instance.resultsdir")/old.1/"*.results.txt)
        files=$(grep -oP '^Statistics:\s+\d+\s+Files' "$oldfile")
        files=$(echo "$files" | grep -oP '\d+')
    fi



    local progress; progress=$(echo "$sofar * 100 / $files " | bc)    

    flock -n -x /tmp/gobcron.flock true || echo "currently, lock /tmp/gobcron.flock is taken by process with PID $(cat /tmp/gobcron.flock)"
    local gobbase; gobbase=$(ps -eadf | grep benchexec | tr -s ' '| rev | cut -f 1 -d " " | rev | xargs dirname | head -n 1)    
    local gobtag; gobtag=$(cat "$gobbase/results/current/tag")

    echo -e "$progress% progressed for tag $gobtag from $gobbase \n"
    drawbar "$progress"
}

main