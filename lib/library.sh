#!/bin/bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

[ -n "${GOBCRON_LIBRARY}" ] && return; GOBCRON_LIBRARY=0; # pragma once

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/conf.sh"
source "$SCRIPTDIR/zulip.sh"

initconf "$SCRIPTDIR/.."

localversion () {
    local base; base="$(conf "instance.basedir")"
    local analyzerdir; analyzerdir=$(conf "instance.analyzerdir")
    local output; output=$(git -C "$base/$analyzerdir" show --oneline | awk '{ print $1 }')
    echo "${output:0:7}"
}

repoversion () {
    local repo; repo="$(conf "instance.gitrepo")"
    local branch; branch="$(conf "instance.branch")"
    local output; output=$(git ls-remote "$repo" --branch "$branch" | awk '{ print $1 }')
    echo "${output:0:7}"
}

oldversion () {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir="$(conf "instance.resultsdir")"
    cat "$base/$resultsdir/old.1/commithash"
}

currentversion () {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir="$(conf "instance.resultsdir")"
    cat "$base/$resultsdir/current/commithash"
}

# obtain most recent goblint analyzer commits & compile
compile () {
    if [[ "$(localversion)" == "$(repoversion)" ]]; then echo "skipping compilation, since local $(localversion) is same as repo version $(repoversion)"; return 0; fi
    local base; base="$(conf "instance.basedir")"
    local analyzerdir; analyzerdir=$(conf "instance.analyzerdir")
    cd "$base"
    rm -rf "$analyzerdir"
    git clone --branch "$(conf "instance.branch")" "$(conf "instance.gitrepo")" "$analyzerdir"
    make -C "$base/$analyzerdir" setup
    make -C "$base/$analyzerdir" release
    cd -
}

# rotate result folder
rotate () {
    local base; base="$(conf "instance.basedir")"
    local localver; localver="$(localversion)"
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    local current; current=$(currentversion )
    local historysize; historysize=$(conf "instance.historysize")
    local analyzerdir; analyzerdir=$(conf "instance.analyzerdir")
    local tag; tag=$(conf "instance.tag")
    rm -rf "$base/$resultsdir/old.$historysize"
    seq 1  "$((historysize-1))" | tac | xargs -n1 bash -c 'mv '"$base/$resultsdir"'/old.$0 '"$base/$resultsdir"'/old.$(($0+1))'
    mv     "$base/$resultsdir/current" "$base/$resultsdir/old.1"
    mkdir  "$base/$resultsdir/current"
    echo   "$localver" > "$base/$resultsdir/current/commithash"
    echo   "$tag" > "$base/$resultsdir/current/tag"
    date +%Y%m%d-%H%M > "$base/$resultsdir/current/date"
    git -C "$base/$analyzerdir" log --oneline "$current".."$localver" > "$base/$resultsdir/current/lastchanges"
}

# re-generate date--commithash symlinks
symlinks () {
    local base; base="$(conf "instance.basedir")"
    local commitsdir; commitsdir=$(conf "instance.commitsdir")
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    rm -rf "$base/$commitsdir"
    mkdir "$base/$commitsdir"
    ls "$base/$resultsdir"/*/commithash | xargs -n1 bash -c 'ln -s $(dirname $0) '"$base/$commitsdir"'/$(cat $(dirname $0)/date)--$(cat $0)-$(cat $(dirname $0)/tag)'
}

# create difftables and result table
# parameters: $1=accumulator
function difftables () {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    local -n accu=$1
    local current; current="$(cat "$base/$resultsdir"/current/commithash)";
    local old; old="$(cat "$base/$resultsdir"/old.1/commithash)";
    local gobcron; gobcron=$(mktemp -t gobcronXXXX)
    local benchmarkname; benchmarkname=$(conf "instance.benchmark" | xargs -n1 basename -s .xml)
    echo "diffing commit $current with old $old"
    accu="$gobcron"
    echo "| Task | last: $old | current: $current | :red_triangle_up: score | difftable" > "$gobcron"
    echo "|---|---|---|---|---" >> "$gobcron"
    echo "usingtmp file $gobcron"
    #retrieve taskgroups
    declare -a runsets=($(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 30 | grep "run sets:" | awk '{ $1=""; $2=""; print $0 }' | tr "," " "))
    for taskgroup in "${runsets[@]}"
    do
	echo "trying  with taskgroup $taskgroup"
	local file; file=$(ls "$base/$resultsdir"/current/*"$taskgroup".xml.bz2) 
	if [ ! -f "$file" ]; then continue; fi
	source "$base/pyenv/bin/activate"
	table-generator -q -n "$taskgroup" -o "$base/$resultsdir/current/diff2previous" "$file"
	table-generator -q -n "$taskgroup"-current -f statistics-tex -o "$base/$resultsdir/current/diff2previous" "$file"
	deactivate
	local currentscore=0 ;
	local oldscore=0 ;
	local diff=0 ;
	currentscore=$(cat "$base/$resultsdir/current/diff2previous"/*"$taskgroup"-current*.statistics.tex | grep -o Score\}.* | sed 's/Score}{\(.*\)}%/\1/')
	local compareto; compareto=$(ls "$base/$resultsdir"/old.1/*"$taskgroup".xml.bz2)
	if [ -f "$compareto" ]; then
	    source "$base/pyenv/bin/activate"
	    table-generator -q -n "$taskgroup" -o "$base/$resultsdir/current/diff2previous" "$file" "$compareto"
	    table-generator -q -n "$taskgroup-old"     -f statistics-tex -o "$base/$resultsdir/current/diff2previous" "$compareto"
	    deactivate
	    oldscore=$(cat "$base/$resultsdir/current/diff2previous"/*"$taskgroup-old"*.statistics.tex | grep -o Score\}.* | sed 's/Score}{\(.*\)}%/\1/')
	    ((currentscore)) || currentscore=0
	    ((oldscore)) || oldscore=0
	    diff="$((currentscore-oldscore))"
	fi
	local line="";
	local difftablesize=0;
	difftablesize=$(cat "$base/$resultsdir/current/diff2previous"/"$taskgroup".diff.csv | tail -n +4 | wc -l)
	echo "scores: $currentscore vs $oldscore"
	[[ "$currentscore" -gt "$oldscore" ]] && line="| $taskgroup | $oldscore | $currentscore | :check: (+ $diff)   | $difftablesize" ;
	[[ "$currentscore" -eq "$oldscore" ]] && line="| $taskgroup | $oldscore | $currentscore | :check_mark: (+/- 0) | $difftablesize" ;
	[[ "$currentscore" -lt "$oldscore" ]] && line="| $taskgroup | $oldscore | $currentscore | :warning: (- $diff) | $difftablesize" ;
	echo "$line" >> "$gobcron"
    done
    rm -f "$base/$resultsdir"/current/diff2previous/*.tex
}

# search git log for noteworthy merges
# parameters: $1=accumulator
function commitinfo () {
    local base; base="$(conf "instance.basedir")"
    local -n output=$1
    output="| commit | comment
|---|---"
    local current; current="$(cat "$base"/results/current/commithash)";
    local old; old="$(cat "$base"/results/old.1/commithash)";
    local IFS; IFS=$'\n'
    echo "git -C $base/analyzer log $old..$current --oneline --merges --invert-grep --grep \"'master' into\""
    local merges; merges=($(git -C "$base/analyzer" log "$old".."$current" --oneline --merges --invert-grep --grep "'master' into"))
    for i in "${merges[@]}"; do
	local id; id="${i:0:7}"
	local message; message=$(echo "$i" | awk '{ $1=""; print $0 }')
	output="$output
| commit $id | $message"
    done
}

# give an overview on the most important information of this benchmark run
# parameters: $1=accumulator
function runinfo() {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    local server; server="$(conf "server.user")@$(conf "server.name")"
    local benchmarkname; benchmarkname=$(conf "instance.benchmark" | xargs -n1 basename -s .xml)
    local -n output=$1
    local runsets; runsets=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 30 | grep "run sets:" | awk '{ $1=""; $2=""; print $0 }')
    local runs; runs=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 14 | grep "parallel runs:" | awk '{ $1=""; $2=""; print $0 }')
    local config; config=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 14 | grep "options:" | awk '{ $1=""; $2=""; print $0 }')
    local memory; memory=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 14 | grep "memory:" | awk '{ $1=""; $2=""; print $0 }')
    local time; time=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 30 | grep "time:" | awk '{ $1=""; $2=""; print $0 }')
    local revision; revision=$(cat "$base/$resultsdir/current/commithash")
    local date; date=$(cat "$base/$resultsdir/current/date")
    local path; path="sftp://$server$base/$(conf "instance.commitsdir")/$date--$revision"
    
    output="|SV-Comp config | value
|---|---
| taskgroups | $runsets
| parallel runers | $runs
| config file | $config
| task memory | $memory
| time limit | $time
| results    | $path"
}
