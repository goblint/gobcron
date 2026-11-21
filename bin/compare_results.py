"""Compare non-demo BenchExec run sets and write summary.md and detailed tables
under CURRENT/diff2previous/. Scores and CPU-time deltas are current minus old.
"""

import argparse
import csv
import io
import subprocess
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import NamedTuple


# This table definition requests BenchExec's per-task score. The weighted
# scores in finalscores.csv answer a different question and aren't inputs here.
COLUMNS = Path(__file__).resolve().parents[1] / "conf/compare-results.xml"
NA = "N/A"


class Task(NamedTuple):
    """One run's cells in the column order defined by conf/compare-results.xml."""

    status: str    # What the analyzer reported, e.g. "true" or "TIMEOUT".
    category: str  # How BenchExec judged it, e.g. "correct" or "wrong".
    score: str     # Points awarded for this result; wrong answers can be negative.
    cpu: str       # CPU seconds as text; an empty cell means no measurement.


def run_sets(directory):
    """Map each non-demo run set in one result directory to its result XML path.

    For example, if bench.results.txt lists "run sets: reach, overflow_demo",
    return {"reach": directory / "bench.results.reach.xml.bz2"}. Read the names
    from the log so that XML files for individual blocks aren't counted again.
    A listed non-demo set must have exactly one matching result.
    """
    groups = {}
    logs = sorted(directory.glob("*.results*.txt"))
    if not logs:
        raise ValueError(f"{directory}: no BenchExec run sets found")
    for log in logs:
        # The text log and its XML files share the prefix before ".results.".
        prefix = log.name.rsplit(".results.", 1)[0]
        with log.open() as f:
            # For "run sets: A, B", look for <prefix>.results.{A,B}.xml.bz2.
            # Globbing all XML files could also pick up subsets of A or B.
            names = next((line.split(":", 1)[1] for line in f
                          if line.startswith("run sets:")), None)
        if names is None:
            raise ValueError(f"{log}: no 'run sets:' header")
        for name in map(str.strip, names.split(",")):
            if not name or Path(name).name != name:
                raise ValueError(f"{log}: invalid run set name {name!r}")
            # BenchExec can append ".<task block>" to the rundefinition name.
            if name.partition(".")[0].endswith("_demo"):
                continue
            # The name is our join key across directories. If two logs claim
            # it on the same side, we cannot tell which XML to compare.
            if name in groups:
                raise ValueError(f"{directory}: ambiguous run set {name!r}")
            path = directory / f"{prefix}.results.{name}.xml.bz2"
            # A listed run with missing XML is incomplete input. Only a name
            # absent from the other run's header counts as added or removed.
            if not path.is_file():
                raise FileNotFoundError(path)
            groups[name] = path
    return groups


def task_rows(files):
    """Return one row per BenchExec task identity, with one Task per input file.

    BenchExec aligns tasks (including property and expected verdict) and supplies
    their scores. The leading task-ID columns vary; the result columns come last.
    """
    # Read the full table from stdout (-o -). A diff-only table would drop
    # unchanged tasks, whose scores and CPU times still belong in the totals.
    table = subprocess.check_output(
        ["table-generator", "-q", "-x", COLUMNS, "-f", "csv", "--no-diff",
         "-o", "-", *files], text=True)
    # BenchExec calls this format "csv", but separates fields with tabs.
    # Consecutive tabs must survive parsing: they stand for missing cells.
    rows = csv.reader(io.StringIO(table), delimiter="\t", quoting=csv.QUOTE_NONE)
    # Skip the tool and run-set headers. The last column can include a CPU
    # time unit, so use the three preceding titles to find the column header.
    for header in rows:
        if header[-4:-1] == ["status", "category", "score"]:
            break
    else:
        raise ValueError(f"{files}: missing comparison columns")
    # A two-run row ends with [current's four fields][baseline's four fields].
    # Counting from the right skips the variable number of task-ID columns.
    start = len(header) - len(Task._fields) * len(files)
    offsets = range(start, len(header), len(Task._fields))
    # The header loop has consumed the column titles. Each remaining row is
    # one task, e.g. [Task("true", "correct", "2", "1.3"), Task("", "", "", "")]
    # for a current result with no matching task in the baseline.
    return [[Task(*row[i:i + 4]) for i in offsets] for row in rows]


def totals(tasks):
    """Return (score, wrong count, CPU seconds) for one side of a run set.

    A missing score or CPU measurement makes that total unavailable (None).
    """
    # Blank groups of cells are placeholders for tasks only in the other run.
    present = [task for task in tasks if any(task)]

    def total(values):
        # Cells are strings: "0" is a measurement, "" makes the sum incomplete.
        # Sum decimal seconds before truncating for display: two tasks taking
        # 0.6 s each contribute 1.2 s, not two zeros.
        return sum(map(Decimal, values)) if values and all(values) else None

    # "wrong" is a judgement, not a verdict: "false" may be the correct
    # answer for a task. Count the category rather than inspecting the status.
    return (total([task.score for task in present]),
            sum(task.category == "wrong" for task in present),
            total([task.cpu for task in present]))


def duration(seconds):
    # Format magnitudes only. The caller attaches the sign to the whole
    # duration so a decrease of 61 s reads "-000h 01m 01s".
    minutes, seconds = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours:03}h {minutes:02}m {seconds:02}s"


def compare_group(name, current, old):
    """Build one summary row; either XML path may be None for a one-sided group."""
    rows = task_rows([p for p in (current, old) if p is not None])
    # Current is first and baseline last. For a one-sided group the sole
    # entry is at both indices, so only read the side whose file exists.
    old_score, _, old_time = totals(row[-1] for row in rows) if old else (None, None, None)
    score, wrong, cpu = totals(row[0] for row in rows) if current else (None, None, None)
    runtime = NA if cpu is None else duration(cpu)
    if cpu is not None and old_time is not None:
        # Subtract the original totals, not their rounded display values.
        # A positive time delta means the current run used more CPU time.
        delta = cpu - old_time
        runtime += f" ({'+' if delta >= 0 else '-'}{duration(abs(delta))})"

    changed = NA
    if current and old:
        # An added or removed task has a blank status on its missing side;
        # comparing aligned statuses counts it even if no diff file was written.
        changed = sum(a.status != b.status for a, b in rows)
        # Score change is a net sum. Two verdicts can change in opposite
        # directions, so a score delta of zero need not mean identical results.
        delta_score = NA
        if score is not None and old_score is not None:
            diff = score - old_score
            icon = ":trophy:" if diff > 0 else ":warning:" if diff < 0 else ":check_mark:"
            delta_score = f"{icon} ({diff:+})"
    else:
        # A whole run set appeared or disappeared. There is no second score
        # to subtract; using zero here would invent a gain or a regression.
        delta_score = "N/A (added)" if current else "N/A (removed)"

    return [name, old_score, score, delta_score, changed, wrong, runtime]


def detailed_tables(name, current, old, out):
    # Clear optional outputs before regenerating: BenchExec omits the diff
    # files when zero or all verdicts changed, leaving stale files on a rerun.
    for ext in ("html", "csv"):
        (out / f"{name}.diff.{ext}").unlink(missing_ok=True)
        if not (current and old):
            # A previous comparison may have had both sides. This invocation
            # won't regenerate its paired table, so don't leave that table up.
            (out / f"{name}.table.{ext}").unlink(missing_ok=True)
    generate = ["table-generator", "-q", "-n", name, "-o", out]
    # Uploads include the current run on its own as well as the side-by-side
    # table when a baseline exists.
    if current:
        subprocess.run([*generate, current], check=True)
    if current and old:
        subprocess.run([*generate, current, old], check=True)


def label(directory):
    # Directory names like "current" rotate. Tag and commit identify the run
    # even after the report has been uploaded or its directory renamed.
    return " / ".join((directory / key).read_text().strip() for key in ("tag", "commithash"))


def compare(current, old):
    new = run_sets(current)
    # On the first nightly run there may be no baseline directory. Generate
    # the current tables anyway, with each run set marked as added.
    previous = run_sets(old) if old.exists() else {}
    out = current / "diff2previous"
    out.mkdir(exist_ok=True)
    rows = [["Task", f"last: {label(old) if old.exists() else NA}", f"current: {label(current)}",
             ":red_triangle_up: score", "Changed tasks", "#:siren: wrong verdicts", ":hourglass: CPU time"],
            ["---"] * 7]
    # Include baseline-only groups so a removed run set is visible in the report.
    for name in sorted(new.keys() | previous.keys()):
        rows.append(compare_group(name, new.get(name), previous.get(name)))
        detailed_tables(name, new.get(name), previous.get(name), out)
    report = out / "summary.md"
    # Zulip renders this as Markdown. Escape literal pipes in names and tags
    # so they don't introduce extra columns; keep numeric zero distinct from N/A.
    report.write_text("".join("| " + " | ".join(
        NA if cell is None else str(cell).replace("|", r"\|") for cell in row
    ) + " |\n" for row in rows))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("current", type=Path, help="current result directory (comparison output goes here)")
    parser.add_argument("old", type=Path, help="baseline result directory (may be absent on the first run)")
    args = parser.parse_args()
    try:
        compare(args.current.resolve(), args.old.resolve())
    except (OSError, ValueError, InvalidOperation, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"{parser.prog}: {exc}\n")
