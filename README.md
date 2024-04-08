# Gobcron

a process to regularly run a [benchexec](https://github.com/sosy-lab/benchexec)-based [SV-COMP-benchmark](https://gitlab.com/sosy-lab/benchmarking/sv-benchmarks) on a tool in order to asssess bugs to the efficiency of the tool in question. 


## Installation
```bash
sudo add-apt-repository ppa:sosy-lab/benchmarking
sudo apt install benchexec jq grep sed gawk git curl
git clone https://github.com/DrMichaelPetter/gobcron.git
cd gobcron
```

in order to communicate the run information back to you, you should [add a bot to your zulip instance](https://zulip.com/help/add-a-bot-or-integration) and store bot-email and bot-apikey for later use in gobcron's configuration.

## Configuration
```bash
cp conf/gobcron.json conf/gobcron.user.json
```
and modify ```conf/gobcron.user.json``` to your liking. You can safely remove all non-edited properties, as they are filled with the default-values from the original file.

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
        "memory": "2GB"
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
        "branch": "widening-experiment"
    }
}
```
- get inspired by other options from [gobcron.json](conf/gobcron.json)
## Running once
```
bin/nightly.sh
```

## Anchoring in the crontab
start your crontab editor with ```crontab -e``` and enter a line like:
```
# m h  dom mon dow   command
5 22 * * * bash -c "/home/user/gobcron/bin/nightly.sh"
# end of crontab

```
in order to start the nightly run at 22:05
