#!/bin/bash

# Run the SV-COMP27 verification levels through the normal gobcron workflow.
set -euo pipefail

BASEDIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
cd "$BASEDIR"

explain=false
config_args=()
run_args=(--enqueue --skipchangecheck)
while (($#)); do
    case "$1" in
        -c | --conf)
            if (($# < 2)) || [[ ! -f "$2" ]]; then
                echo "Expected an existing gobcron config after $1" >&2
                exit 1
            fi
            config_args+=(-c "$(realpath "$2")")
            shift 2
            ;;
        -e | --explain)
            explain=true
            shift
            ;;
        -h | --help)
            echo "Usage: $0 [-c FILE.json] [--explain] [--disablezulip] [--skipreport]"
            echo "Run SV-COMP27 level00 through level05 sequentially (no validation configs)."
            echo "Inherits gobcron settings, optionally overlaid with -c FILE.json."
            echo "Uses bin/run.sh with time limit 900s and wall-time limit 903s."
            echo "Normal analyzer rebuilds, result rotation, reporting, and uploads apply."
            exit 0
            ;;
        --disablezulip | --skipreport)
            run_args+=("$1")
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Enumerate before run.sh rebuilds/replaces the analyzer checkout. This also works
# when the checkout is absent and run.sh needs to clone it first.
# Paths are relative to the analyzer directory, as expected by Goblint.
# Each entry pairs a config path with its pinned short analyzer commit hash.
levels=(
    "conf/svcomp27/level00.json  d4663fe"
    "../level00-nounrolling.json d4663fe"
    "conf/svcomp27/level01.json  d4663fe"
    "conf/svcomp27/level02.json  d4663fe"
    "../subpoly.json             0e1769d"
 #configs may be commented out by a hash
    "conf/svcomp27/level03.json  d4663fe"
    "conf/svcomp27/level04.json  d4663fe"
    "conf/svcomp27/level05.json  d4663fe"
    "../level05-gasAndInit.json  d4663fe"
)

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/gobcron-levels.XXXXXX")
trap 'rm -f "$tmpdir"/*.json; rmdir "$tmpdir"' EXIT

for entry in "${levels[@]}"; do
    read -r config commit <<< "$entry"
    level=$(basename "$config" .json)
    overlay="$tmpdir/$level.json"
    jq -n --arg level "$level" --arg config "$config" --arg commit "$commit" '{instance: {
        commit: $commit,
        tag: ("svcomp27-" + $level),
        benchconf: ["conf/svcomp27/common.json", "conf/svcomp27/verify.json", $config],
        portfoliomode: false,
        timelimit: "900",
        walltimelimit: "903",
	historysize: "20"
    }}' > "$overlay"

    echo "=== $level @ $commit ==="
    command=(bin/run.sh "${config_args[@]}" -c "$overlay" "${run_args[@]}")
    # run.sh handles --explain immediately, so it must come after all overrides.
    if "$explain"; then
        command+=(--explain)
    fi
    "${command[@]}"
done
