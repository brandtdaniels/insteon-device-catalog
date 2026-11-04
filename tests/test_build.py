"""Tests for the checks scripts/build.py makes beyond what the schemas say.

Run from the repository's root: python3 -I -m unittest discover -s tests
"""

import copy
import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))

import build  # noqa: E402
import jsonschema  # noqa: E402

VALIDATOR = jsonschema.Draft202012Validator(json.loads((build.ROOT / "schema" / "command-set.schema.json").read_text()))


def problems(command_set):
    """What the build reports for a command set: its schema errors, or the build's own checks once
    the schema passes."""
    schema_errors = [error.message for error in VALIDATOR.iter_errors(command_set)]

    return schema_errors or build.command_set_problems(command_set)


def io_linc_with(state_holding):
    """The catalog's I/O Linc command set with the relay's stateHolding replaced."""
    command_set = copy.deepcopy(json.loads((build.ROOT / "commandSets" / "ioLinc.json").read_text()))
    relay = next(group_type for group_type in command_set["groupTypes"] if group_type["kind"] == "relay")
    relay["stateHolding"] = state_holding

    return command_set


class StateHoldingTests(unittest.TestCase):
    def test_a_relay_no_flag_releases_always_holds_its_state(self):
        command_set = io_linc_with({"releasedBy": [], "restState": "off"})

        self.assertEqual(problems(command_set), [])

    def test_a_relay_no_flag_releases_cannot_pulse_on_every_command(self):
        command_set = io_linc_with({"releasedBy": [], "restState": "off", "pulsesOnEveryCommandWhen": [["momentary"]]})

        self.assertEqual(problems(command_set), ["the relay group type's stateHolding has pulsesOnEveryCommandWhen, but no releasedBy flag releases the relay"])


if __name__ == "__main__":
    unittest.main()
