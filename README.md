# Gobcron

a process to regularly run a [benchexec](https://github.com/sosy-lab/benchexec)-based [SV-COMP-benchmark](https://gitlab.com/sosy-lab/benchmarking/sv-benchmarks) on a tool in order to asssess bugs to the efficiency of the tool in question. 


## Installation
```bash
sudo add-apt-repository ppa:sosy-lab/benchmarking
sudo apt install pv make gcc-multilib benchexec jq grep sed gawk git curl node-json5 opam autoconf libgmp-dev libmpfr-dev pkg-config php-json-schema python3-venv python3-check-jsonschema
git clone https://github.com/goblint/gobcron.git
cd gobcron
```

in order to communicate the run information back to you, you should [add a bot to your zulip instance](https://goblint.zulipchat.com/#settings/your-bots) and store bot-email and bot-apikey for later use in gobcron's configuration.

## Configuration

You need to create a reasonable initial ```conf/gobcron.user.json``` file after installation. You can do that manually via copy/modify ```conf/gobcron.json``` or call the semi-interactive
```bash
myserver:/home/huber/gobcron$ bin/init.sh
```
and review/modify ```conf/gobcron.user.json``` to your satisfaction. All non-mentioned properties, are sourced default-values from the original ```conf/gobcron.json``` file.

### Example Use Cases
- to set up a nightly run on the mainline analyzer, use a config like:
```json
{
    "server": {
        "name": "server.amazon.com",
        "user": "huber",
        "threads": "80",
        "memory": "2GB"
    },
    "zulip": {
        "bot": {
            "email": "bot@myinstance.zulipchat.com",
            "apikey": "GARBLEDNONSENSE"
        },
        "mode": "stream",
        "stream": "svcomp-nightly"
    },
    "instance": {
        "basedir": "/home/huber/gobcron",
        "svbenchdir": "/home/huber/sv-benchmarks"
    }
}
```
- to set up a one-shot on a specific branch,  notifying the users with IDs ```4711007,4998451``` on the zulip instance, use a config like:
```json
{
    "server": {
        "name": "laptop",
        "user": "huber",
        "threads": "20",
        "memory": "1GB"
    },
    "zulip": {
        "bot": {
            "email": "bot@myinstance.zulipchat.com",
            "apikey": "GARBLEDNONSENSE"
        },
        "mode": "4711007,4998451"
    },
    "instance": {
        "basedir": "/home/huber/gobcron",
        "svbenchdir": "/home/huber/sv-benchmarks",
        "gitrepo": "https://github.com/huber4711/analyzer.git",
        "branch": "widening-experiment",
        "commit": "471169",
        "benchconf": "conf/svcomp22.json",
        "tag": "hubers-widening"
    }
}
```
- get inspired by other options from [gobcron.json](conf/gobcron.json)

- the popular ```benchconf``` parameter specifies a conf.json parameter file to be used during all the goblint runs in your benchmark. Its addressed relative to the analyzer directory

# Running once

check your config first:
```bash
myserver:/home/huber/gobcron$ bin/run.sh --explain
```

either start a default run with:
```bash
myserver:/home/huber/gobcron$ bin/run.sh
```
or start a custom run with parameters obtained via `bin/run.sh -h`:
```bash
myserver:/home/huber/gobcron$ bin/run.sh --conf mygobcron.json --disablezulip --skipchangecheck
```

# Running in sequence

A sequence of comparable runs can now be efficiently chained by waiting on the lockfile with gobcron's ```bin/run.sh -q``` parameter. This makes most sense, if combined with several custom user configurations
loaded via ```bin/run.sh -c conf/gobcron.tagname.json```. For example:

```bash
# check the individual configurations via the conf.sh tool:
myserver:/home/huber/gobcron$ bin/run.sh -c conf/gobcron.baseline.json --explain
myserver:/home/huber/gobcron$ bin/run.sh -c conf/gobcron.newfeature.json --explain

# start the individual runs one after the other; I recommend doing that inside a detached screen environment
myserver:/home/huber/gobcron$ screen -S baseline -dm bash -c "bin/run.sh -c conf/gobcron.baseline.json"
myserver:/home/huber/gobcron$ screen -S newfeature -dm bash -c "bin/run.sh -q --skipchangecheck -c conf/gobcron.newfeature.json"
```
Now, the baseline run starts and takes the lock, until its execution finished, and newfeature then directly takes over and starts the benchmark run it has been waiting for. Wrapping the calls in screen will make it possible for you to inspect progress of each benchmark, should you be interested in that. As soon as each benchmark is terminated, the screen closes, though.

# Running regularly
## systemd for regularly scheduled execution

You can also use systemd's timer units for a scheduled run:
- make sure that systemd is present even when the user goblint is logged out, and timers are respected with ```loginctl enable-linger goblint```
- create the file ```.config/systemd/user/gobcron.service``` : 
```
[Unit]
Description=Runs an SVCOMP goblint benchmark

[Service]
Type=oneshot
Environment="PATH=/usr/lib/ccache/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"
WorkingDirectory=/home/goblint/gobcron
ExecStart=/home/goblint/gobcron/bin/run.sh

[Install]
WantedBy=default.target
```

- create the file ```.config/systemd/user/gobcron.timer``` :
```
[Unit]
Description=A nightly 22:00 benchmark run of goblint SV-Comp

[Timer]
OnCalendar=Mon-Sun *-*-* 22:00:00
Unit=gobcron.service

[Install]
WantedBy=default.target
```

- enable the timer and service:
```
systemctl --user enable gobcron.service
systemctl --user enable gobcron.timer
systemctl --user start gobcron.timer
systemctl --user list-timers
```
- you can manually trigger the gobcron job by ```systemctl --user start gobcron``` or schedule a one-time run with  
```
systemd-run --user --on-calendar="2025-01-30 20:01:35" bash -c "cd gobcron;bin/run.sh"
```

## Legacy: Anchoring in the crontab
start your crontab editor with ```crontab -e``` and enter a line like:
```
# m h  dom mon dow   command
5 22 * * * bash -c "/home/huber/gobcron/bin/run.sh"
# end of crontab

```
in order to start the nightly run at 22:05


# Miscellaneous 

### status of the current run

You may get an idea of the progress of the current benchmark by checking
```bash
myserver:/home/huber/gobcron$ bin/progress.sh
```

### configuration issues

You may view and/or alter the current default configuration, including gobcron.user.json
```bash
myserver:/home/huber/gobcron$ bin/conf.sh -s instance.basedir=/home/huber -a
```
and eventually play with configurations via `-g` and `-s`.

### create comparison tables 

You may revisit, which results are available under which tag names, and then create a set of comparison tables between exactly these benchmark run results.
```bash
myserver:/home/huber/gobcron$ bin/bigcomparison.sh -l
available tags:
    [TAG] ............................................ [DIRECTORY]
    tag3 ............................................. ( results/current )
    tag2 ............................................. ( results/old.1 )
    tag4 ............................................. ( results/old.2 )
    tag1 ............................................. ( results/old.3 )
myserver:/home/huber/gobcron$ bin/bigcomparison.sh -t tag1 -t tag2 -t tag3
```

### Compare two runs by run set

From the repository root, give the **current run first** and the **baseline second**:

```bash
# Generate the comparison and print the Markdown summary.
bin/statistics.sh -f results/current -f results/old.1

# Or generate the files directly, then read the summary when needed.
.venv/bin/python3 bin/compare_results.py results/current results/old.1
cat results/current/diff2previous/summary.md
```

[`bin/compare_results.py`](bin/compare_results.py) needs BenchExec's `table-generator` on `PATH`.
Each existing input directory must contain `tag`, `commithash`, a BenchExec results text
file with a `run sets:` header, and the corresponding `*.results.<name>.xml.bz2` files.
Run definitions ending in `_demo` are skipped, including names with a task-block suffix
such as `SV-COMP26_no-overflow_demo.C.no-overflow.Example`. On a first run, the Python
helper accepts a baseline path that does not yet exist.

The summary has one row per non-demo run set found on either side:

| Column | Meaning |
|---|---|
| Last / current score and score change | Sum of BenchExec task scores for each run; change is current minus baseline. The weighted portfolio-level and metacategory scores are reported separately by `bin/compare_csv.py`. |
| Changed tasks | Number of aligned task rows whose status differs. A reported status on one side and an absent task on the other also count as a change. |
| Wrong verdicts | Number of current tasks BenchExec classified as `wrong`. |
| CPU time | Sum of current task CPU times, with the signed difference from baseline when available. |

An added or removed run set is labelled explicitly and has no delta. `N/A` means a
value is unavailable, not zero. Detailed HTML and CSV tables are written alongside
`summary.md`. BenchExec can omit the `.diff.*` tables when **none or all** of the
statuses differ; use the summary's **Changed tasks** count to distinguish those cases.

### Performance statistics

`conf/tablegen.xml` extracts per-task performance statistics into
`results/current/<tag>.table.csv`; these columns are also preserved in `finalscores.csv`:

| Columns | Meaning |
|---|---|
| `cputime`, `memory` | BenchExec CPU time in seconds and peak process memory in bytes. |
| `varcount`, `evalcount` | Last reported solver-variable and constraint-evaluation counts. |
| `allocated_total_mb`, `allocated_minor_mb`, `allocated_major_mb`, `allocated_promoted_mb` | Cumulative OCaml allocation volumes, in decimal MB. Major allocations include promoted allocations; total avoids counting promotions twice. |
| `heap_max_mb` | Peak OCaml major-heap size, in decimal MB. |
| `gc_minor_collections`, `gc_major_collections`, `gc_compactions` | Last reported garbage-collection and compaction counts. |
| `frontc_cputime`, `frontc_walltime` | C parsing times, in seconds. |
| `cabs2cil_cputime`, `cabs2cil_walltime` | C-to-CIL conversion times, in seconds. |
| `createcfg_cputime`, `createcfg_walltime` | Goblint CFG construction times, in seconds. |
| `solving_cputime`, `solving_walltime` | Solver execution times, including nested postsolver work, in seconds. |
| `witness_cputime`, `witness_walltime` | YAML witness generation and writing times, in seconds. |

Timing is enabled by default through `instance.options`. If overriding this option,
include `<option name="--enable">dbg.timing.enabled</option>` to retain phase timings.
The timing measurements are inclusive; they do not separately attribute GC time.
`createcfg_*` covers Goblint's CFG construction, not the earlier CIL-internal CFG
preparation and loop unrolling.

Heap/GC values come from periodic solver snapshots and may be absent for short runs
or stop before the run finishes. Missing measurements remain empty, rather than zero.
Extraction uses the last matching snapshot or timing region in the log; portfolio
values are not summed across configurations, and a missing measurement in a later
configuration can leave an earlier configuration's value.

## sending zulip messages from command line or scripts

If you have configured your configration with a valid zulip bot, you may send messages to the zulip id of your choice via ```bin/zulip.sh [ID] "My message"```
