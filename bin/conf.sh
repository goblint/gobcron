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
    echo "  -a                  --all              : get complete configuration as it is in memory" 
    echo "  -g key              --get key          : get the value of a configuration key from memory"
    echo "  -s key=value        --set key=value    : set the value of a configuration key temporarily during this bash session"
}

VALID_ARGS=$(getopt -o ahg:s: --long all,help,get:,set: -- "$@")
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

helpme

exit 0
