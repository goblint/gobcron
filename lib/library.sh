#!/bin/bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script via: \$ source $0" >&2
    exit 33
fi

[ -n "${GOBCRON_LIBRARY}" ] && return; GOBCRON_LIBRARY=0; # pragma once

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/conf.sh"
source "$SCRIPTDIR/zulip.sh"

initconf "$SCRIPTDIR/.."

function DEBUG () {
    [ "$_DEBUG" == "on" ] &&  "$@"
}

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
    cat "$base/$resultsdir/$(conf "instance.compareto")/commithash"
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
    git -C "$analyzerdir" checkout "$(conf "instance.commit")"
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
    mkdir -p "$base/$resultsdir"
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

# push to webserver via WebDAV
function pushtoweb () {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    local protocol; protocol="$(conf "upload.protocol")"
    local url; url="$(conf "upload.url")"
    local user; user="$(conf "upload.user")"
    local pass; pass="$(conf "upload.password")"

    local date="$(cat "$base/$resultsdir/current/date")"
    local current="$(cat "$base/$resultsdir/current/commithash")"
    local tag="$(cat "$base/$resultsdir/current/tag")"
    local uploadfile="$tag-$date--$current.tar.gz"
    tar czf "/tmp/$uploadfile" "$base/$resultsdir/current/diff2previous" "$base/$resultsdir"/current/*.logfiles.zip 2>/dev/null
    if [ "$protocol" == "webdav" ]; then
        # currently only webdav/https is supported
        if [ -z "$user" ]; then # anonymous upload
            #DEBUG echo curl -4 --silent -T "/tmp/$uploadfile" "$url"
            curl -4 --silent -T "/tmp/$uploadfile" "$url" > /dev/null
        else # authenticated upload
            #DEBUG echo curl -4 --silent -T "/tmp/$uploadfile" -u "$user:$pass" "$url"
            curl -4 --silent -T "/tmp/$uploadfile" -u "$user:$pass" "$url" > /dev/null
        fi
    else
        echo ""
        return
    fi
    #tar tzf "/tmp/$uploadfile"
    rm -rf "/tmp/$uploadfile"
    echo "$uploadfile"
}

# compare two result folders and create a comparison table
# parameters: $1=accumulator , $2=comparisondir1 , $3=comparisondir2
function compareresults () {
    function wrong () {
        echo $(cat $1 | grep -o "Wrong}{}{Count}".* | sed 's/Wrong}{}{Count}{\(.*\)}%/\1/' )
    }
    function score () {
        echo $(cat $1 | grep -o "Score}".* | sed 's/Score}{\(.*\)}%/\1/' )
    }
    function timing () {
        echo $(cat $1 | grep -o "Cputime}{All}{}{Sum}{".* | sed 's/Cputime}{All}{}{Sum}{\(.*\)\..*}%/\1/' )
    }
    local -n accu=$1
    local comparison1;
    local comparison2;
    comparison1="$2"
    comparison2="$3"
    local current; current="$(cat "$comparison1"/commithash)";
    local currenttag; currenttag="$(cat "$comparison1"/tag)";
    local old; old="$(cat "$comparison2"/commithash)";
    local oldtag; oldtag="$(cat "$comparison2"/tag)";
    local gobcron; gobcron=$(mktemp -t gobcronXXXX)
    local benchmarkname; benchmarkname=$(conf "instance.benchmark" | xargs -n1 basename -s .xml)
    DEBUG echo "diffing commit $current with old $old"
    accu="$gobcron"
    echo "| Task | last: $oldtag / $old | current: $currenttag / $current | :red_triangle_up: score | difftable | #:siren: wrong verdicts | :hourglass: runtime" > "$gobcron"
    echo "|---|---|---|---|---|---|---" >> "$gobcron"
    DEBUG echo "using tmp file $gobcron"
    #retrieve taskgroups
    declare -a runsets=($(cat "$comparison1/$benchmarkname"*.txt| head -n 30 | grep "run sets:" | awk '{ $1=""; $2=""; print $0 }' | tr "," " "))
    for taskgroup in "${runsets[@]}"
    do
	    DEBUG echo "trying  with taskgroup $taskgroup"
	    local file; file=$(ls "$comparison1"/*"$taskgroup".xml.bz2)
	    if [ ! -f "$file" ]; then continue; fi
	    table-generator -q -n "$taskgroup" -o "$comparison1/diff2previous" "$file"
	    table-generator -q -n "$taskgroup"-current -f statistics-tex -o "$comparison1/diff2previous" "$file"
	    local currentscore=0 ;
	    local oldscore=0 ;
	    local diff=0 ;
        local wrongcount=0 ;
        local statsfile;
        statsfile=$(echo "$comparison1/diff2previous"/*"$taskgroup"-current*.statistics.tex | head -n 1)
        wrongcount=$(wrong "$statsfile" )
        currentscore=$(score  "$statsfile" )
        local currentruntime=0;
        currentruntime=$(timing "$statsfile" )
        local prettyruntime=0;
        prettyruntime=$(printf "%03dh %02dm %02ds" $((currentruntime/3600)) $((currentruntime%3600/60)) $((currentruntime%60)))
        # prettyruntime=$(printf "%02dh %02dm %02ds (%d seconds)" $((currentruntime/3600)) $((currentruntime%3600/60)) $((currentruntime%60)) $currentruntime)
	    local compareto; compareto=$(ls "$comparison2"/*"$taskgroup".xml.bz2)
	    if [ -f "$compareto" ]; then
	        table-generator -q -n "$taskgroup" -o "$comparison1/diff2previous" "$file" "$compareto"
	        table-generator -q -n "$taskgroup-old"     -f statistics-tex -o "$comparison1/diff2previous" "$compareto"
	        local oldstatsfile;
            oldstatsfile=$(echo   "$comparison1/diff2previous"/*"$taskgroup-old"*.statistics.tex | head -n 1 )
            oldscore=$(score "$oldstatsfile" )
            oldruntime=$(timing "$oldstatsfile" )
	        ((currentscore)) || currentscore=0
	        ((oldscore)) || oldscore=0
	        diff="$((currentscore-oldscore))"
            local timediff="$((currentruntime-oldruntime))"
            prettyruntime="$prettyruntime  (:red_triangle_up: $(printf "%+dmins %+dsecs" $((timediff/60)) $((timediff%60)) ))"
	    fi
	    local line="";
	    local difftablesize=0;
	    difftablesize=$(cat "$comparison1/diff2previous"/"$taskgroup".diff.csv 2> /dev/null | tail -n +4 | wc -l)
	    DEBUG echo "scores: $currentscore vs $oldscore"
        taskgroup="${taskgroup#*_}"  # remove everything before _
        taskgroup="${taskgroup%%.*}" # remove additional stuff after .
	    [[ "$currentscore" -gt "$oldscore" ]] && line="| $taskgroup | $oldscore | $currentscore | :trophy: (+ $diff)  | $difftablesize | $wrongcount | $prettyruntime" ;
	    [[ "$currentscore" -eq "$oldscore" ]] && line="| $taskgroup | $oldscore | $currentscore | :check_mark: (+/-0) | $difftablesize | $wrongcount | $prettyruntime" ;
	    [[ "$currentscore" -lt "$oldscore" ]] && line="| $taskgroup | $oldscore | $currentscore | :warning: ($diff)   | $difftablesize | $wrongcount | $prettyruntime" ;
	    echo "$line" >> "$gobcron"
    done
    rm -f "$comparison1"/diff2previous/*.tex
}

# search git log for noteworthy merges
# parameters: $1=accumulator
function commitinfo () {
    local base; base="$(conf "instance.basedir")"
    local resultsdir; resultsdir=$(conf "instance.resultsdir")
    local analyzerdir; analyzerdir=$(conf "instance.analyzerdir")
    local -n output=$1
    if [ ! -f "$base/$resultsdir/$(conf "instance.compareto")/commithash" ]; then return; fi
    output="| commit | comment 
|---|---"
    local current; current="$(cat "$base/$resultsdir"/current/commithash)";
    local old; old="$(cat "$base/$resultsdir/$(conf "instance.compareto")"/commithash)";
    local IFS; IFS=$'\n'
    DEBUG echo "git -C $base/$analyzerdir log $old..$current --oneline --merges --invert-grep --grep \"'master' into\""
    local merges; merges=($(git -C "$base/$analyzerdir" log "$old".."$current" --oneline --merges --invert-grep --grep "'master' into"))
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
    local config; config=$(conf "instance.benchconf")
    local gitinfo; gitinfo="$(conf "instance.gitrepo") [$(conf "instance.branch")] @ $(conf "instance.commit")"
    local memory; memory=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 14 | grep "memory:" | head -n 1 | awk '{ $1=""; $2=""; print $0 }')
    local time; time=$(cat "$base/$resultsdir/current/$benchmarkname"*.txt| head -n 30 | grep "time:" | awk '{ $1=""; $2=""; print $0 }')
    local revision; revision=$(cat "$base/$resultsdir/current/commithash")
    local date; date=$(cat "$base/$resultsdir/current/date")
    local path; path="sftp://$server$base/$(conf "instance.commitsdir")/$date--$revision-$(cat "$base/$resultsdir/current/tag")"
    
    output="|SV-Comp config | value
|---|---
| codebase | $gitinfo
| config file | $config
| parallel runers | $runs
| task memory | $memory
| time limit | $time
| results    | $path"
}
