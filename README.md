# Gobcron

a process to regularly run a benchexec-based benchmark on a tool in order to asssess bugs to the efficiency of the tool in question. 


## Installation
```bash
sudo add-apt-repository ppa:sosy-lab/benchmarking
sudo apt install benchexec jq grep sed gawk git curl
git clone https://github.com/DrMichaelPetter/gobcron.git
cd gobcron
```

## Configuration
```bash
cp conf/gobcron.json conf/gobcron.user.json
```
and modify ```conf/gobcron.user.json``` to your liking. You can safely remove all non-edited properties, as they are filled with the default-values from the original file.

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
