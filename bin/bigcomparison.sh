#!/bin/bash
source lib/library.sh

_DEBUG=on

function DEBUG () {
    [ "$_DEBUG" == "on" ] &&  "$@"
}

function listtags {
    function listtag {
        local dir="$1"
        local tag="$(cat "$dir")"
        local line="................................................."
        printf "    %s %s ( %s )\n" $tag "${line:${#tag}}" "$(dirname $dir)"
    }
    echo "available tags:"
    printf "    %s %s %s\n" "[TAG]" "............................................" "[DIRECTORY]"
    ls results/*/tag | xargs -n 1 | xargs -I@ -P4 bash -c "$(declare -f listtag); listtag @"
}

function helpme {
    local progname; progname=$(basename "$0")
    echo "usage: $progname [options] [-t tag1] [-t tag2] ..." 
    echo "  -t tag              --tag tag          : specify a tag for the comparison"
    echo ""
    listtags
}

VALID_ARGS=$(getopt -o l,h,t: --long list,help,tag: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi
declare -a interest=()

function addinterest {
    local name="$1"
    local potential=$(find results/*/tag -exec bash -c '[[ $(cat {}) == "$0" ]] && echo {}' "$name" \;)
    [[ -n "$potential" ]] && interest+=("$(dirname $potential)")
}



eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -l | --list)
        listtags
        shift
        exit 0
        ;;
    -t | --tag)
        addinterest "$2"
        shift 2
        ;;
    -h | --help)
        helpme
        shift
        exit 0
        ;;
    --) shift; 
        break 
        ;;
  esac
done


function performstatistics () {

    firstresult="$(ls -d -1 results/* | head -n 1)"
    declare -a runsets=($(cat "$firstresult/"*.txt| head -n 30 | grep "run sets:" | awk '{ $1=""; $2=""; print $0 }' | tr "," " "))

    rm -rf evaluation
    mkdir -p evaluation/tex
    mkdir -p evaluation/crossprod

    printf "Performing statistics for:"
    for result in "${interest[@]}"
    do
        printf "%s, " "$result"
    done
    printf "\n"

    for taskgroup in "${runsets[@]}"
    do
        echo "Taskgroup: $taskgroup"
    
        for result in "${interest[@]}"
        do
            tagname="$(cat "$result/tag")"
            echo "   Resulttag: $tagname"
            file="$(echo results/old.1/*"$taskgroup".xml.bz2 | head -n 1)"
            table-generator -q -n "$tagname--$taskgroup" -o "evaluation/tex" -f statistics-tex "$file"
            echo "       Score: $(cat evaluation/tex/"$tagname"--"$taskgroup".statistics.tex | grep -o Score\}.* | sed 's/Score}{\(.*\)}%/\1/')"
            echo "       #Wrong: $(cat evaluation/tex/"$tagname"--"$taskgroup".statistics.tex | grep -o Wrong\}\{\}\{Count\}.* | sed 's/Wrong}{}{Count}{\(.*\)}%/\1/')"
            echo "       Cputime $(cat evaluation/tex/"$tagname"--"$taskgroup".statistics.tex | grep -o Cputime\}\{All\}\{\}\{Sum\}\{.* | sed 's/Cputime}{All}{}{Sum}{\(.*\)\..*}%/\1/')"
        done
    
        sep="/*$taskgroup.xml.bz2 "
        printf -v string "%s$sep" "${interest[@]}"
        table-generator -q -o "evaluation/crossprod" -n "$taskgroup" $string
    done

}

[[ "${#interest[@]}" == "0" ]] && printf "\n%s\n\n" " ERROR: No tags specified" && helpme && exit 1 
[[ "${#interest[@]}" != "0" ]] && performstatistics
