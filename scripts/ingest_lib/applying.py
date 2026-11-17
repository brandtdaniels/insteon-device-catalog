"""Applies a reviewed draft to the profile files, then proves the catalog still builds.

This is a maintainer's action. It refuses a working tree that holds other work, a report it did
not expect to read, and a catalog that has moved since the report was drafted; and it puts every
file back when the build fails.
"""

import json
import pathlib
import subprocess
import sys

from . import drafting, patching


def run_build(root):
    """Runs the repository's build in root. Returns whether it passed, and what it said."""
    result = subprocess.run(
        [sys.executable, "-I", str(pathlib.Path(root) / "scripts" / "build.py")],
        cwd=root,
        capture_output=True,
        text=True,
    )

    return result.returncode == 0, (result.stdout + result.stderr).strip()


def tree_problems(root, allowed):
    """Why the working tree is not clean, ignoring the files named in allowed (paths relative to root)."""
    try:
        result = subprocess.run(["git", "-C", str(root), "status", "--porcelain"], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return ["cannot tell whether the working tree is clean"]

    others = [line for line in result.stdout.splitlines() if line[3:] not in allowed]

    return ["the working tree has changes of its own; commit or stash them first"] if others else []


def apply_report(report, root, build_runner=run_build, allowed=()):
    """Applies every drafted change in the report. Returns an exit status and the lines to print."""
    root = pathlib.Path(root)

    if not isinstance(report, dict) or report.get("format") != drafting.REPORT_FORMAT or report.get("lane") != "observation":
        return 1, ["not an observation report this tool wrote"]

    observations = report.get("observations")

    if not isinstance(observations, list):
        return 1, ["the report has no observations"]

    if any(isinstance(item, dict) and item.get("outcome") == "rejected" for item in observations):
        return 1, ["the report holds a rejected observation; fix it and draft again"]

    problems = tree_problems(root, set(allowed))

    if problems:
        return 1, problems

    changes = [
        change
        for item in observations
        if isinstance(item, dict) and item.get("outcome") == "drafted"
        for change in item.get("changes", [])
    ]

    if not changes:
        return 0, ["nothing to apply: the report drafts no changes"]

    for change in changes:
        problems = patching.change_problems(change)

        if problems:
            return 1, problems

    originals, profiles, outcomes = {}, {}, []

    for change in changes:
        path = root / change["file"]

        if change["file"] not in profiles:
            try:
                originals[change["file"]] = path.read_text()
                profiles[change["file"]] = json.loads(originals[change["file"]])
            except (OSError, ValueError):
                return 1, [f"cannot read {change['file']}"]

        outcome = patching.apply_change(profiles[change["file"]], change)

        if outcome not in ("applied", "already"):
            return 1, [f"{change['file']}: {outcome}"]

        outcomes.append(outcome)

    if set(outcomes) == {"already"}:
        return 0, ["already applied: the catalog holds every change in the report"]

    written = [name for name in profiles if patching.dump(profiles[name]) != originals[name]]

    for name in written:
        (root / name).write_text(patching.dump(profiles[name]))

    passed, output = build_runner(root)

    if not passed:
        for name in written:
            (root / name).write_text(originals[name])

        return 1, ["the build failed, so every file was put back:", output]

    return 0, [f"applied {outcomes.count('applied')} changes to {len(written)} files and the build passed"] + [f"  {name}" for name in written]
