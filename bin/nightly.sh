#!/bin/bash

# cron-job for nightly SV-Comp; started via cron demon, configure via:
# EDITOR=emacs crontab -e

# import communication with zulip
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

# FORCERUN=true deactivates check for new commits and check for running benchmarks
FORCERUN=false
shopt -s extglob

#################################### start the actual program ###################################
basedir="$(conf "instance.basedir")"
cd "$basedir"
benchstarttime=$(date +%H:%M)

#from library.sh
localhash=$(currentversion)

#from library.sh
upstreamhash=$(repoversion)

zulip () {
    local message; message="$1"
    local who; who="$(conf "zulip.mode")"
    if [ "$who" == "stream" ]; then
        local stream; stream="$(conf "zulip.stream")"
        zulipstream "$stream" "commit $upstreamhash" "$message"
    else
        zulipmessage "$who" "$message"
    fi
}

zulipmessage "$(conf zulip.user.MichaelP)" "cron job started: localhash: $localhash ; upstreamhash: $upstreamhash"

# skip if there are no new commits
if [ "$localhash" == "$upstreamhash" ] && [ "$FORCERUN" != "true" ]; then
    echo "no changes in repository since last time, skipping!";
    zulipmessage "$(conf zulip.user.MichaelP)" "current version $localhash is still up-to-date, GitHub version is $upstreamhash so we are skipping nightly"
    exit 1 ;
fi

#from library.sh
compile

# skip if goblint is already running
goblintjobs=$(ps -eadf| grep "./goblint " | wc -l)
if [ "$goblintjobs" -gt "1" ]  && [ "$FORCERUN" != "true" ]; then
    echo "goblint is already running, skipping!";
    zulipmessage "$(conf zulip.user.MichaelP)" "GitHub $upstreamhash is newer as $localhash, but we found more than one goblintjob running"
    exit 1;
fi

#from library.sh
rotate

#from library.sh
symlinks 

#from library.sh
commitinfo out

zulip "$(conf server.user)@$(conf server.name) started a nightly sv-comp run for commit $upstreamhash [differing from $localhash](https://github.com/goblint/analyzer/compare/$localhash...$upstreamhash) at $benchstarttime."
zulip "$out"

# relocate goblint-nightly.template.xml to the correct folder on this server
rm -f "$basedir/nightly.xml"
cat "$basedir/conf/nightly-template.xml" | sed "s#SVBENCHMARKPREFIX#$(conf "instance.svbenchdir")#" > "$basedir/nightly.xml"

# perform the actual benchmark
source "$basedir/pyenv/bin/activate"
cd "$basedir/$(conf "instance.analyzerdir")"
benchexec --read-only-dir / --overlay-dir . --overlay-dir /home --outputpath "$basedir/$(conf "instance.resultsdir")/current" --numOfThreads "$(conf "server.threads")" "$basedir/nightly.xml"
rm -f "$basedir/nightly.xml"
cd -
deactivate

# compare the result to the previous one
#from library.sh
difftables acc
acc="$(cat "$acc")"

#from library.sh
runinfo rundata

zulip "sv-comp run for commit ${upstreamhash:0:7} terminated at $(date +%H:%M)"
zulip "$rundata"
zulip "$acc"


exit 0
