#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote
from urllib.request import urlopen
import xml.etree.ElementTree as ET

API = "https://gitlab.com/api/v4/projects/sosy-lab%2Fsv-comp%2Fbench-defs"
BENCHMARKS_URL = "https://gitlab.com/sosy-lab/benchmarking/sv-benchmarks.git"
DOCTYPE = (
    '<!DOCTYPE benchmark PUBLIC '
    '"+//IDN sosy-lab.org//DTD BenchExec benchmark 2.3//EN" '
    '"https://www.sosy-lab.org/benchexec/benchmark-2.3.dtd">'
)


def download(endpoint):
    with urlopen(API + endpoint, timeout=120) as response:
        return response.read()


def api_json(endpoint):
    return json.loads(download(endpoint))


def list_refs(limit):
    tags = api_json(
        f"/repository/tags?order_by=updated&sort=desc&per_page={limit}"
    )
    commits = api_json(
        f"/repository/commits?ref_name=main&per_page={limit}"
    )
    print("Recent tags (most recently updated first):")
    for tag in tags:
        print(f"  {tag['name']}  {tag['commit']['id']}")
    if not tags:
        print("  No tags found.")

    print("\nRecent commits on main (newest first):")
    for commit in commits:
        print(
            f"  {commit['id']}  {commit['committed_date'][:10]}"
            f"  {commit['title']}"
        )
    print("\nUse a tag or full commit SHA with --ref to update the environment.")


def ref_limit(value):
    limit = int(value)
    if not 1 <= limit <= 100:
        raise argparse.ArgumentTypeError("must be between 1 and 100")
    return limit


def read_config(path):
    if not path.exists():
        return {}
    # Match gobcron's support for full-line // comments.
    text = re.sub(r"^\s*//.*$", "", path.read_text(), flags=re.MULTILINE)
    return json.loads(text)


def git(directory, *args):
    return subprocess.check_output(
        ["git", "-C", str(directory), *args], text=True
    ).strip()


def atomic_write(path, text):
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def make_template(source, revision):
    root = ET.fromstring(source)
    if root.tag != "benchmark" or root.get("tool") != "goblint":
        raise ValueError("Unexpected upstream benchmark format")

    runs = root.findall("rundefinition")
    if not runs or any(
        not run.get("name", "").startswith("SV-COMP") for run in runs
    ):
        raise ValueError("Missing or unexpected SV-COMP run definitions")

    root.attrib.clear()
    root.set("tool", "goblint")

    # Let gobcron supply hardware-independent limits and analyzer options.
    for child in list(root):
        if child.tag in {"require", "option"}:
            root.remove(child)

    for element in root.iter():
        if element.text:
            element.text = element.text.replace(
                "../sv-benchmarks/", "SVBENCHMARKPREFIX/"
            )

    # Use a temporary element to position the literal template placeholder.
    marker = ET.Element("gobcron-options-placeholder")
    root.insert(list(root).index(runs[0]), marker)
    ET.indent(root, space="  ")
    body = ET.tostring(root, encoding="unicode")
    body = body.replace(
        "<gobcron-options-placeholder />", "SVBENCHMARKOPTIONS"
    )

    return (
        '<?xml version="1.0"?>\n'
        f"{DOCTYPE}\n"
        f"<!-- Generated from bench-defs commit {revision} -->\n"
        f"{body}\n"
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Synchronize gobcron's benchmark environment to a bench-defs "
            "revision (main by default)."
        ),
        epilog="""Changes made when updating:
  1. Resolve --ref to an immutable bench-defs commit SHA.
  2. Fetch and check out the sv-benchmarks submodule revision recorded at
     that commit in instance.svbenchdir (detached HEAD; requires a clean,
     existing checkout).
  3. Replace conf/nightly-template.xml with the commit's goblint.xml,
     removing upstream hardware requirements and top-level analyzer options
     and resource limits, and inserting gobcron's path/option placeholders.
  4. Set instance.goblintxmltag in conf/gobcron.user.json to that commit SHA.
     Other configuration values are preserved, but JSON comments are removed.

Configuration is read from conf/gobcron.json and conf/gobcron.user.json
under --base; the template and user configuration are also written there.
Relative instance.svbenchdir paths are resolved against --base. By default,
--base is the parent of this script's bin/ directory, regardless of the
current working directory. Use it only to target another installation.

Analyzer configuration selection (benchconf/portfolio) is
unchanged. Updates acquire the same lock as run.sh.

--list-refs only queries GitLab and displays tags and commits; it does not
modify files or checkouts.
""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--ref", default="main", help="bench-defs branch/tag/SHA (default: %(default)s)"
    )
    parser.add_argument(
        "--list-refs",
        action="store_true",
        help="list recent bench-defs tags and main commits without updating",
    )
    parser.add_argument(
        "--limit",
        type=ref_limit,
        default=10,
        help="number of tags and commits to list (1-100, default: 10)",
    )
    parser.add_argument(
        "--base",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help=(
            "gobcron installation to update "
            "(default: parent of this script's bin/ directory)"
        ),
    )
    args = parser.parse_args()
    if args.list_refs:
        list_refs(args.limit)
        return

    base = args.base.resolve()

    # Use the same lock as run.sh; do not remove the lock file.
    with open("/tmp/gobcron.flock", "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        user_path = base / "conf/gobcron.user.json"
        defaults = read_config(base / "conf/gobcron.json")
        user = read_config(user_path)
        instance = {
            **defaults.get("instance", {}),
            **user.get("instance", {}),
        }
        benchmarks = Path(instance["svbenchdir"]).expanduser()
        if not benchmarks.is_absolute():
            benchmarks = base / benchmarks

        # Require an existing, clean checkout before making changes.
        git(benchmarks, "rev-parse", "--show-toplevel")
        if git(benchmarks, "status", "--porcelain"):
            raise RuntimeError(f"Checkout has local changes: {benchmarks}")

        commit = api_json(
            "/repository/commits/" + quote(args.ref, safe="")
        )["id"]

        # Paginate so the submodule lookup does not depend on root-tree size.
        benchmark_commit = None
        page = 1
        while True:
            entries = api_json(
                f"/repository/tree?ref={commit}&per_page=100&page={page}"
            )
            if not entries:
                break
            for entry in entries:
                if entry["path"] == "sv-benchmarks":
                    if entry["mode"] != "160000":
                        raise RuntimeError("sv-benchmarks is not a submodule")
                    benchmark_commit = entry["id"]
            page += 1

        if benchmark_commit is None:
            raise RuntimeError("bench-defs has no sv-benchmarks submodule")

        source = download(
            "/repository/files/benchmark-defs%2Fgoblint.xml/raw"
            f"?ref={commit}"
        )
        template = make_template(source, commit)

        git(benchmarks, "fetch", BENCHMARKS_URL, benchmark_commit)
        git(benchmarks, "checkout", "--detach", benchmark_commit)

        user.setdefault("instance", {})["goblintxmltag"] = commit
        atomic_write(base / "conf/nightly-template.xml", template)
        atomic_write(user_path, json.dumps(user, indent=4) + "\n")

        print(f"bench-defs:    {commit}")
        print(f"sv-benchmarks: {benchmark_commit}")
        print(f"Template:      {base / 'conf/nightly-template.xml'}")
        print(f"Configuration: {user_path}")


if __name__ == "__main__":
    main()
