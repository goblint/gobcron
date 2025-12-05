#!/bin/bash

# cron-job for nightly SV-Comp; started via cron demon, configure via:
# EDITOR=emacs crontab -e

# import communication with zulip
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

# FORCERUN=true deactivates check for new commits and check for running benchmarks
FORCERUN=false
shopt -s extglob

function helpme {
    echo "usage: $0 [options]" 
    echo "options:"
    echo "  -h                  --help             : show this help"
    echo "  -c [FILE.json]      --conf [FILE.json] : interpret the configuration based on file FILE.json"
    echo "  -a                  --all              : get complete configuration as it is in memory" 
    echo "  -g key              --get key          : get the value of a configuration key from memory"
    echo "  -G key              --getset key       : get the value of a configuration key as an array from memory"
    echo "  -s key=value        --set key=value    : set the value of a configuration key temporarily during this bash session"
}

VALID_ARGS=$(getopt -o ahg:G:s:c: --long all,help,get,getset:,set:,conf: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -g | --get)
        conf "$2"
        shift 2
        ;;
    -G | --getset)
        confset "$2"
        shift 2
        ;;
    -c | --conf)
        CONFFILE="$2"
        source lib/conf.sh
        updateconfigwithfile "$2"
        shift 2
        ;;
    -a | --all)
        shift 1
        conf ""
        ;;
    -s | --set)
        updateconf "$2"
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

exit 0
