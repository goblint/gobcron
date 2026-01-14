#!/bin/bash

# cron-job for nightly SV-Comp; started via cron demon, configure via:
# EDITOR=emacs crontab -e

# import communication with zulip
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"

# FORCERUN=true deactivates check for new commits and check for running benchmarks
FORCERUN="false"
FORCECOMPILE="false"
SKIPREPORT="false"
DISABLEZULIP="false"
CONFFILE="conf/gobcron.user.conf"
ENQUEUE="-n"
shopt -s extglob

VALID_ARGS=$(getopt -o e,h,c:,q --long help,explain,enqueue,skipreport,skipchangecheck,disablezulip,conf: -- "$@")

function helpme {
    echo "usage: $0 [options]" 
    echo "options:"
    echo "  -h                  --help             : show this help"
    echo "  -e                  --explain          : print the actual commands that will be executed"
    echo "  -q                  --enqueue          : enqueue this run for later execution"
    echo "                      --skipreport       : do not perform the report"
    echo "                      --skipchangecheck  : run the analyzer, even though result/current has the latest commit id"
    echo "                      --disablezulip     : STDOUT instead of zulip"
    echo "  -c [FILE.json]      --conf [FILE.json] : provide a specific config file"

}


function zulip () {
    local message; message="$1"
    local who; who="$(conf "zulip.mode")"

    if [ "$DISABLEZULIP" == "true" ]; then
        echo "$message"
        return
    fi

    if [ "$who" == "stream" ]; then
        local stream; stream="$(conf "zulip.stream")"
        zulipstream "$stream" "commit $upstreamhash" "$message"
    else
        recipients="$(conf "zulip.mode")"
        recipients=(${recipients//,/ })
        for recipient in "${recipients[@]}"; do
            zulipmessage "$recipient" "$message"
        done
    fi
}

function whatwillhappen () {
    conf
    echo ""
    echo " ... which means:"
    echo "--------------------------"
    echo ""

    basedir="$(conf "instance.basedir")"
    echo -e "current conf-file is: $CONFFILE           ... change with -c parameter"
    echo -e "basedir will be: $basedir"
    echo -e "tag will be: $(conf "instance.tag")"
    echo -e "  -> result goes to $basedir/$(conf "instance.resultsdir")/$(date +%Y%m%d-%H%M)--COMMITID-$(conf "instance.tag")"
    repocommand="git clone --branch $(conf "instance.branch") $(conf "instance.gitrepo") && git checkout $(conf "instance.commit")"
    echo -e "reference git repo will be:\n  $repocommand"
    portfoliomode=$(conf "instance.portfoliomode")
    if [ "$portfoliomode" == "true" ]; then
        confs="Portfolio: $(conf "instance.portfolio")"
    else
        confs="Configs: $(./bin/conf.sh -G instance.benchconf | jq -r 'map("<option name=\"--conf\">"+.+"</option> ") | add')"
    fi
    echo -e "$confs"
    benchexeccommand="\n  benchexec --read-only-dir / --overlay-dir . --overlay-dir /home 
        --outputpath    $basedir/$(conf "instance.resultsdir")/current/ 
        --memorylimit   $(conf "server.memory") 
        --numOfThreads  $(conf "server.threads") 
        --timelimit     $(conf "instance.timelimit") 
        --walltimelimit $(conf "instance.walltimelimit") 
        --name          $(conf "instance.tag") 
        --no-hyperthreading
        $basedir/run.xml"

    echo -e "benchmark command is: $benchexeccommand"

    if [ "$DISABLEZULIP" == "true" ]; then
        echo -e "parameter --disablezulip is set, so gobcron will not communicate via zulip"
    else
        who="$(conf "zulip.mode")"
        if [ "$who" == "stream" ]; then
            echo -e "results are communicated via zulip bot $(conf "zulip.bot.email") to stream $(conf "zulip.stream")"
        else
            echo -e "results are communicated via zulip bot $(conf "zulip.bot.email") to user $(conf "zulip.mode")"
        fi
    fi
    upload="$(conf "upload.protocol")"
    if [ "$upload" == "webdav" ]; then
        echo -e "results are uploaded via WebDAV to $(conf "upload.url")"
    else
        echo -e "results are not uploaded"
    fi
    
    if [ "$FORCECOMPILE" == "true" ]; then
        echo -e "parameter --skipchangecheck is set, so gobcron will compile the analyzer"
    fi

    if [ "$SKIPREPORT" == "true" ]; then
        echo -e "parameter --skipreport is set, so gobcron will not perform the report"
    fi

    if [ "$ENQUEUE" == "-n" ]; then
        echo -e "parameter --enqueue is not set, so gobcron will terminate if lock /tmp/gobcron.flock is taken"
    else
        echo -e "parameter --enqueue is set, so gobcron will run as soon as the lock /tmp/gobcron.flock is free"
    fi
    flock -n -x /tmp/gobcron.flock true || echo "currently, lock /tmp/gobcron.flock is taken by process with PID $(cat /tmp/gobcron.flock), so gobcron will not run now"


}

function main () {
    #################################### start the actual program ###################################
    basedir="$(conf "instance.basedir")"
    cd "$basedir"

    # skip if gobcron is already active
    flock -n -x /tmp/gobcron.flock true || echo "waiting to acquire lock /tmp/gobcron.flock from process with PID $(cat /tmp/gobcron.flock)"
    exec 100>/tmp/gobcron.flock || exit 1
    flock "$ENQUEUE" 100 || { echo "gobcron is already running, skipping!"; exit 1; }
    trap "rm -f /tmp/gobcron.flock" EXIT
    echo "lock acquired"
    echo "$$" > /tmp/gobcron.flock

    # maintain a webserver for status information in the background during the run
    #local web;
    #web=$(./bin/webstatus.sh &)
    #trap "kill $web" EXIT

    benchstarttime=$(date +%H:%M)
    benchstartseconds=$(date +%s)

    DEBUG echo "basedir is: $basedir"

    local currenthash;  currenthash=$(currentversion) # version in results/current
    local upstreamhash; upstreamhash=$(repoversion)   # version in repo
    local analyzerhash; analyzerhash=$(localversion)  # version in analyzer


    if [[ "$FORCECOMPILE" == "true" ]]; then
        compile
    else
        # check if there are changes between the repository version and the results/current version
        if [[ "$currenthash" == "$upstreamhash" ]]; then
            echo "No difference between the repository and the run in $base/$(conf "instance.resultsdir") skipping execution!";
            exit 0
        else
            compile
        fi
    fi

    # skip if goblint is already running
    goblintjobs=$(ps -eadf| grep "./goblint " | wc -l)
    if [ "$goblintjobs" -gt "1" ]  && [ "$FORCERUN" != "true" ]; then
        echo "goblint is already running, skipping!";
        exit 1;
    fi

    #from library.sh
    rotate

    #from library.sh
    symlinks 

    #from library.sh
    commitinfo out


    zulip "$(conf server.user)@$(conf server.name) started a $(conf instance.tag) sv-comp run for commit $upstreamhash [differing from $currenthash](https://github.com/goblint/analyzer/compare/$currenthash...$upstreamhash) at $benchstarttime."
    zulip "$out"

    # relocate goblint-nightly.template.xml to the correct folder on this server
    rm -f "$basedir/run.xml"
    portfoliomode=$(conf "instance.portfoliomode")
    if [ "$portfoliomode" == "true" ]; then
        confs="<option name=\"--portfolio-conf\">$(conf "instance.portfolio")</option>"
        ln -sf "$basedir/analyzer/scripts/sv-comp/goblint_runner.py" "$basedir/analyzer"
    else
        confs="$(./bin/conf.sh -G instance.benchconf | jq -r 'map("<option name=\"--conf\">"+.+"</option> ") | add')"
    fi
    cat "$basedir/conf/nightly-template.xml" | sed "s#SVBENCHMARKPREFIX#$(conf "instance.svbenchdir")#" | sed "s#SVBENCHMARKOPTIONS#$(conf "instance.options") $confs#" > "$basedir/run.xml"

    # perform the actual benchmark
    cd "$basedir/$(conf "instance.analyzerdir")"
    benchexec --read-only-dir / --overlay-dir . --overlay-dir /home \
        --outputpath    "$basedir/$(conf "instance.resultsdir")/current/" \
        --memorylimit   "$(conf "server.memory")" \
        --numOfThreads  "$(conf "server.threads")" \
        --timelimit     "$(conf "instance.timelimit")" \
        --walltimelimit "$(conf "instance.walltimelimit")" \
        --name          "$(conf "instance.tag")" \
        --no-hyperthreading \
        "$basedir/run.xml"

    rm -f "$basedir/run.xml"
    cd -

    # compare the result to the previous one/ compareto
    #from library.sh
    compareresults acc \
        "$basedir/$(conf "instance.resultsdir")/current" \
        "$basedir/$(conf "instance.resultsdir")/$(conf "instance.compareto")"
    acc="$(cat "$acc")"

    #from library.sh
    runinfo rundata

    scoring
    zulip "Confirmed true results per portfolio level:"
    zulip "$(< "$basedir/$(conf "instance.resultsdir")/current/totalscore.confirmedtrue.md")"
    zulip "Resource overconsumption per portfolio level:"
    zulip "$(< "$basedir/$(conf "instance.resultsdir")/current/totalscore.outofresources.md")"
    zulip "Score per meta-category:"
    zulip "$(< "$basedir/$(conf "instance.resultsdir")/current/finalscorespercat.md")"
    zulip "Overall score per portfolio level:"
    zulip "$(< "$basedir/$(conf "instance.resultsdir")/current/totalscore.md")"

    uploadfile="$(pushtoweb)"

    benchstartseconds=$((($(date +%s)-$benchstartseconds)))
    benchmarkhours=$((benchstartseconds/3600))
    benchmarkminutes=$(printf "%02d" $((benchstartseconds/60%60)))

    if [ "$uploadfile" != "" ]; then
        zulip "SV-Comp run for commit ${upstreamhash:0:7} terminated at $(date +%H:%M) after $benchmarkhours:$benchmarkminutes h. [Results]($(conf "upload.url")/$uploadfile) are now available."
    else
        zulip "SV-Comp run for commit ${upstreamhash:0:7} terminated at $(date +%H:%M) after $benchmarkhours:$benchmarkminutes h."
    fi

    [[ "$SKIPREPORT" != "true" ]] && (zulip "$rundata" ; zulip "$acc")

    exit 0
}



if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -t | --tag)
        addinterest "$2"
        shift 2
        ;;
    -c | --conf)
        [[ ! -f "$2" ]] && echo "Error: file '$2' not found" && exit 1
        CONFFILE="$2"
        source lib/conf.sh
        updateconfigwithfile "$2"
        echo "updated config temporarily with '$2', resulting into:"
        conf
        shift 2
        ;;
    -q | --enqueue)
        ENQUEUE="-e"
        shift
        ;;
    -e | --explain)
        FORCERUN="true"
        whatwillhappen
        exit 0
        ;;
    --skipchangecheck)
        FORCECOMPILE="true"
        shift
        ;;
    --skipreport)
        SKIPREPORT="true"
        shift
        ;;
    --disablezulip)
        DISABLEZULIP="true"
        shift
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

main
