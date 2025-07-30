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
    echo "  -t tag              --tag tag          : specify a tag for the synthesis"
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


function performsynth () {

    firstresult="$(ls -d -1 results/* | head -n 1)"
    declare -a runsets=($(cat "$firstresult/"*.txt| head -n 30 | grep "run sets:" | awk '{ $1=""; $2=""; print $0 }' | tr "," " "))

    rm -rf synthesis
    mkdir -p synthesis
    cd synthesis

    printf "Performing synthesis:\n"
    for result in "${interest[@]}"
    do
        tagname=$(cat ../"$result"/tag)
        resultsfile=$(ls ../"$result"/*.txt | head -n 1)
        logfilearchive=$(ls ../"$result"/*.logfiles.zip | head -n 1)
        logfilearchiveprefix=$(basename "$logfilearchive" .zip)
        printf "tag %s: %s\n" "$tagname" "$resultsfile"
        csplit "$resultsfile" -f 'svcomp.' -b '%02d.set' '/^SV-COMP/' '{*}' -q
        rm svcomp.00.set
        for file in svcomp.*.set; do 
            if [[ -f "$file" ]]; then
                catname=$(head -n 1 "$file")
                strings=(
                    "true"
                    "OUT"
                    "TIMEOUT"
                    "unknown"
                )
                for cat in "${strings[@]}"; do
                    grep yml "$file" | grep "$cat" | awk '{print $1}'> "$tagname-$cat-$catname".set
                done
            fi
        done
        rm -f svcomp.*.set

# filter the unknowns for true verdicts -- these are the only ones, that we can even succeed with
        for file in "$tagname"-unknown-*.set; do
            if [[ -f "$file" ]]; then
                catname=$(echo "$file" | sed 's/.*-\(SV-COMP.*\)\.set/\1/')
                touch "$file.trueverdict"
                rm -rf "$file.trueverdict"
                echo "  $catname: $file"
                for line in $(cat "$file"); do
                    line="/home/goblint/sv-benchmarks/c/$line"
                    if [[ $(grep "verdict: true" "$line" | tr ':' ' ' | awk '{print $1}' | head -n 1 | wc -l) -ne 0 ]]; then
                        echo "$line" >> "$file.trueverdict"
                    fi
                done
            fi
        done

# filter the TIMEOUTS for true verdicts -- these are the only ones, that we can even succeed with
        for file in "$tagname"-TIMEOUT-*.set; do
            if [[ -f "$file" ]]; then
                catname=$(echo "$file" | sed 's/.*-\(SV-COMP.*\)\.set/\1/')
                touch "$file.trueverdict"
                rm -rf "$file.trueverdict"
                echo "  $catname: $file"
                for line in $(cat "$file"); do
                    line="/home/goblint/sv-benchmarks/c/$line"
                    if [[ $(grep "verdict: true" "$line" | tr ':' ' ' | awk '{print $1}' | head -n 1 | wc -l) -ne 0 ]]; then
                        echo "$line" >> "$file.trueverdict"
                    fi
                done
            fi
        done


# uncomment the following lines to print the runtime information for each category
#        for file in "$tagname"-true-*.set; do
#            if [[ -f "$file" ]]; then
#                catname=$(echo "$file" | sed 's/.*-\(SV-COMP.*\)\.set/\1/')
#                echo "  $catname: $file"
#                for line in $(cat "$file"); do
#                    line=$(basename "$line")
#                    unzip  -p "$logfilearchive"  "$logfilearchiveprefix"/"$catname"."$line".log | grep "runtime:" | tail -n 1
#                done
#            fi
#        done
    done

}

[[ "${#interest[@]}" == "0" ]] && printf "\n%s\n\n" " ERROR: No tags specified" && helpme && exit 1 
[[ "${#interest[@]}" != "0" ]] && performsynth
