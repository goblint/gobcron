# Gobcron

a process to regularly run a [benchexec](https://github.com/sosy-lab/benchexec)-based [SV-COMP-benchmark](https://gitlab.com/sosy-lab/benchmarking/sv-benchmarks) on a tool in order to asssess bugs to the efficiency of the tool in question. 


## Installation
```bash
sudo add-apt-repository ppa:sosy-lab/benchmarking
sudo apt install benchexec jq grep sed gawk git curl
git clone https://github.com/DrMichaelPetter/gobcron.git
cd gobcron
```

in order to communicate the run information back to you, you should [add a bot to your zulip instance](https://goblint.zulipchat.com/#settings/your-bots) and store bot-email and bot-apikey for later use in gobcron's configuration.

## Configuration

You need to create a reasonable initial ```conf/gobcron.user.json``` file after installation. You can do that manually via copy/modify ```conf/gobcron.json``` or call the semi-interactive
```bash
myserver:/home/huber/gobcron$ ./bin/init.sh
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
- to set up a one-shot on a specific branch,  notifying user ID ```4711007``` on the zulip instance, use a config like:
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
        "mode": "4711007"
    },
    "instance": {
        "basedir": "/home/huber/gobcron",
        "svbenchdir": "/home/huber/sv-benchmarks",
        "gitrepo": "https://github.com/huber4711/analyzer.git",
        "branch": "widening-experiment",
        "benchconf": "conf/svcomp22.json",
        "tag": "hubers-widening"
    }
}
```
- get inspired by other options from [gobcron.json](conf/gobcron.json)

## Running once

check your config first:
```bash
myserver:/home/huber/gobcron$ /bin/run.sh --explain
```

either start a default run with:
```bash
myserver:/home/huber/gobcron$ bin/run.sh
```
or start a custom run with parameters obtained via `bin/run.sh -h`:
```bash
myserver:/home/huber/gobcron$ bin/run.sh --conf mygobcron.json --disablezulip --skipchangecheck
```

## Working in a gobcron folder with provided tools


### configuration topics

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

## Anchoring in the crontab
start your crontab editor with ```crontab -e``` and enter a line like:
```
# m h  dom mon dow   command
5 22 * * * bash -c "/home/huber/gobcron/bin/run.sh"
# end of crontab

```
in order to start the nightly run at 22:05
