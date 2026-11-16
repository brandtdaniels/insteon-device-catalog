"""Turns what a device did into a reviewed draft of the catalog's verification marks.

Usage:
    python3 -I scripts/ingest.py check FILE...
    python3 -I scripts/ingest.py draft FILE... [--report REPORT.json] [--md REPORT.md]
    python3 -I scripts/ingest.py apply REPORT.json

FILE is what `insteon observe` writes. Nothing here merges anything: a maintainer reads the
draft and runs apply, then reviews the diff.
"""

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from ingest_lib import drafting, observation, patching  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent


def catalog_models():
    return {path.stem for path in (ROOT / "devices").glob("*.json")}


def check_command(arguments):
    """Prints whether each file may be drafted from. Files are named by their content's
    fingerprint, because a file name can be an address."""
    models = catalog_models()
    status = 0

    for position, path in enumerate(arguments.files, start=1):
        label = f"observation {position} ({observation.fingerprint(path)})"
        data, errors = observation.load(path)

        if data is not None:
            errors = observation.check(data, models)

        if errors:
            status = 1
            print(f"{label}: not valid")

            for error in errors:
                print(f"  {error}")
        else:
            print(f"{label}: valid")

    return status


def draft_command(arguments):
    """Drafts every file, then writes or prints the report. Exit status: 0 when nothing needs a
    person, 1 when a file was rejected, 2 when something is left for a maintainer."""
    catalog = patching.load_catalog(ROOT)
    report, notes = drafting.draft_files(arguments.files, catalog, set(catalog))
    markdown = drafting.render_markdown(report, notes)

    if arguments.report:
        arguments.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

    if arguments.md:
        arguments.md.write_text(markdown)

    if arguments.report or arguments.md:
        for item in report["observations"]:
            print(f"{item['input']}: {item['outcome']}")
    else:
        print(markdown, end="")

    if report["outcome"] == "rejected":
        return 1

    return 2 if any(item["disagreements"] for item in report["observations"]) else 0


def build_parser():
    parser = argparse.ArgumentParser(prog="ingest.py", description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    check = commands.add_parser(
        "check",
        help="say whether observation files are valid and free of addresses, hosts and paths",
        description="Validates each file against the observation format and scans every text in it for an "
        "Insteon, IP or MAC address, a URL or host name, an email address and a file path. A rejection names "
        "the field and the kind of data, never the data.",
    )
    check.add_argument("files", nargs="+", type=pathlib.Path, metavar="FILE", help="an observation written by `insteon observe`")
    check.set_defaults(run=check_command)

    draft = commands.add_parser(
        "draft",
        help="match observations to profiles and write a report of what they would change",
        description="Checks each file, matches it to a profile by category, subcategory and firmware, and writes "
        "a report: the verification marks it would add, what the catalog already records, and every disagreement "
        "(engine, key, firmware or device) for a maintainer to decide. It writes only verification marks, never "
        "a value, and changes no catalog file. A check the device did not answer is never used. The contributor's "
        "note is shown in the Markdown and copied nowhere. Exit status: 0 nothing needs a person, 1 a file was "
        "rejected, 2 something is left for a maintainer.",
    )
    draft.add_argument("files", nargs="+", type=pathlib.Path, metavar="FILE", help="an observation written by `insteon observe`")
    draft.add_argument("--report", type=pathlib.Path, metavar="PATH", help="write the machine-readable report here, for apply")
    draft.add_argument("--md", type=pathlib.Path, metavar="PATH", help="write the report as Markdown here; without --report or --md it is printed")
    draft.set_defaults(run=draft_command)

    return parser


def main(argv=None):
    arguments = build_parser().parse_args(argv)

    return arguments.run(arguments)


if __name__ == "__main__":
    sys.exit(main())
