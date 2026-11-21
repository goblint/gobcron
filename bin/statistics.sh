#!/bin/bash

# cron-job for nightly SV-Comp; started via cron demon, configure via:
# EDITOR=emacs crontab -e

# import communication with zulip
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

# FORCERUN=true deactivates check for new commits and check for running benchmarks
FORCERUN=false
shopt -s extglob

function DEBUG () {
    [ "$_DEBUG" == "on" ] &&  "$@"
}

function helpme {
    local progname; progname=$(basename "$0")
    echo "usage: $progname [options]" 
    echo "options:"
    echo "  -h                  --help             : show this help"
    echo "  -l                  --list             : list all result tags" 
    echo "  -t tag              --tag tag          : specify a tag for the comparison"
    echo "  -f folder           --folder folder    : specify a folder for the comparison"
    echo "  -d                  --debug            : enable debug output"
    echo " example: $progname -l                          : first list all available tags"
    echo "          $progname -t tag1 -t tag2             : now choose two tags and compare them"
    echo "          $progname -f dir1 -f dir2             : alternatively choose two folders and compare them"
}

function listtags {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    ls "$base/$resultsdir"/*/tag | xargs -n1 bash -c 'echo "$(cat "$0")       ( $0 )"'
}

function comparetags {
    local tags="$1"
    local tag1; tag1=$(echo $tags | awk '{ print $1 }')
    local tag2; tag2=$(echo $tags | awk '{ print $2 }')
    local commitsdir; commitsdir=$(conf "instance.commitsdir")
    local resultsdir; resultsdir=$(conf "instance.resultsdir")

    local result1=$(grep -r $tag1 results/**/tag)
    local result2=$(grep -r $tag2 results/**/tag)
    if [[ "$(wc -l <<< "$result1")" -ne 1 ]]; then
        echo "$tag1 not unique or did not occur in any result"
        exit 1
    fi
    if [[ "$(wc -l <<< "$result2")" -ne 1 ]]; then
        echo "$tag2 not unique or did not occur in any result"
        exit 1
    fi

    DEBUG echo "comparing: $(dirname $result1) with $(dirname $result2)"

    compareresults acc \
        $(dirname $result1) \
        $(dirname $result2) || return 1
    cat "$acc"
}

function comparefolders {
    local folder1="$1" folder2="$2"

    if [[ ! -d "$folder1" ]]; then
        echo "$folder1 is not a directory"
        exit 1
    fi

    if [[ ! -d "$folder2" ]]; then
        echo "$folder2 is not a directory"
        exit 1
    fi

    DEBUG echo "comparing: $folder1 with $folder2"

    compareresults acc \
        "$folder1" \
        "$folder2" || return 1
    cat "$acc"
}

VALID_ARGS=$(getopt -o h,d,l,f:,t: --long help,debug,list,folder:,tag: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

TAGS=""
FOLDERS=()

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -t | --tag)
        TAGS="$TAGS $2"
        shift 2
        ;;
    -f | --folder)
        FOLDERS+=("$2")
        shift 2
        ;;
    -d | --debug)
        _DEBUG="on"
        shift 1
        ;;
    -l | --list)
        shift 1
        listtags
        exit 0
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

if [[ ! -z "$TAGS" ]]; then
    comparetags "$TAGS"
    exit $?
fi

if (( ${#FOLDERS[@]} )); then
    comparefolders "${FOLDERS[@]}"
    exit $?
fi

echo "no tags specified"
helpme

exit 1
