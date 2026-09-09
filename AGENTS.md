# AGENTS.md

Gobcron is a bash-driven automation harness that runs benchexec-based SV-COMP benchmarks of the Goblint analyzer and reports results (Zulip bot, WebDAV upload, comparison tables). It is an operations repo, not a library: there is no test suite or linter; correctness is verified by `bin/run.sh --explain` and dry inspection.

## Layout

- `bin/` — executable entrypoints (`run.sh` main benchmark, `conf.sh` config inspect/edit, `bigcomparison.sh` result tables, `progress.sh`, `init.sh` setup). Python helpers (`applyscore.py`, `stackedgraph.py`, `compare_csv.py`, `computeweights.py`) are invoked from bash.
- `lib/` — sourced-only bash libraries (`library.sh` core logic, `conf.sh` config resolution, `zulip.sh`). `lib/*.sh` must never be executed directly; they are `source`d and guard against direct execution.
- `analyzer/` — a **git clone of the goblint analyzer** (not a submodule), refreshed/built by `bin/run.sh`. Do not edit files here; changes belong upstream at github.com/goblint/analyzer.
- `results/` — benchmark output history. `results/current` is a rotating symlink-managed dir; previous runs live in `results/old.N`. Each results dir contains a `tag` file used by `bigcomparison.sh -t`.
- `conf/gobcron.json` — default config (JSON with `//` comments, stripped via sed before jq). `conf/gobcron.user.json` overrides it; effective config = `jq '.[0] * .[1]'` deep merge of the two.

## Commands

- Inspect what a run would do: `bin/run.sh --explain` (safe, prints resolved config and the benchexec command).
- Full run: `bin/run.sh` — needs benchexec, an sv-benchmarks checkout, a built analyzer, and flock `/tmp/gobcron.flock`. `-q` enqueues on the lock; `-c FILE.json` overlays an extra config; `--disablezulip` prints instead of messaging.
- Python deps live in a repo-local `.venv` (created by `bin/init.sh`, which hardcodes a TUM proxy `--proxy proxy.cit.tum.de:8080` — drop that flag outside that network). Scripts are always called as `.venv/bin/python3 bin/xxx.py` from bash; `applyscore.py` additionally has uv/PEP 723 inline metadata.
- Config inspection: `bin/conf.sh -g <key>` / `-s key=value` / `-a` (see `--help`).

## Gotchas

- Config JSON files contain `//` comments; never parse them with a strict JSON parser — replicate the `sed 's#^\s*//.*##'` strip first.
- `bin/run.sh` skips a run if the commit in `results/current` already matches the repo HEAD; use `--skipchangecheck` to force.
- Stray artifacts at root (`ech`, `echo`, `hs_err_pid*.log`, `*.json~`, `test.sh` scratch file) are debris from past runs, not source.
- Zulip/upload credentials live in `conf/gobcron.user.json`; never commit real keys.
