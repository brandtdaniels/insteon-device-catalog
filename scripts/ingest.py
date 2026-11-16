"""Turns what a device did into a reviewed draft of the catalog's verification marks.

Usage:
    python3 -I scripts/ingest.py check FILE...
    python3 -I scripts/ingest.py draft FILE... [--report REPORT.json] [--md REPORT.md]
    python3 -I scripts/ingest.py apply REPORT.json

FILE is what `insteon observe` writes. Nothing here merges anything: a maintainer reads the
draft and runs apply, then reviews the diff.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from ingest_lib import observation  # noqa: E402

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

    return parser


def main(argv=None):
    arguments = build_parser().parse_args(argv)

    return arguments.run(arguments)


if __name__ == "__main__":
    sys.exit(main())
