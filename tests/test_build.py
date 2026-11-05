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


def catalog_command_set(command_set_id):
    """A copy of one of the catalog's command sets, to change in a test."""
    return copy.deepcopy(json.loads((build.ROOT / "commandSets" / f"{command_set_id}.json").read_text()))


def renamed(command_set, key, old_name, new_name):
    """Renames the item called old_name in the command set's key list, and returns it."""
    item = next(item for item in command_set[key] if item["name"] == old_name)
    item["name"] = new_name

    return item


def extended_value(command_set, name):
    """The command set's extended settings value called name."""
    return next(value for value in command_set["extendedSettings"]["values"] if value["name"] == name)


class CatalogTests(unittest.TestCase):
    def test_every_command_set_in_the_catalog_passes(self):
        for path in sorted((build.ROOT / "commandSets").glob("*.json")):
            with self.subTest(command_set=path.stem):
                self.assertEqual(problems(json.loads(path.read_text())), [])


class OperatingFlagsByteTests(unittest.TestCase):
    def test_a_value_whose_reply_field_holds_operating_flags_needs_flags_query(self):
        command_set = catalog_command_set("openCloseSensor")
        del extended_value(command_set, "configuration")["flagsQuery"]

        self.assertEqual(problems(command_set), ["the configuration value holds the operating flags byte, so it needs flagsQuery"])

    def test_a_value_named_operating_flags_needs_flags_query(self):
        command_set = catalog_command_set("hiddenDoorSensor")
        del extended_value(command_set, "operatingFlags")["flagsQuery"]

        self.assertEqual(problems(command_set), ["the operatingFlags value holds the operating flags byte, so it needs flagsQuery"])

    def test_a_value_named_operating_flags_needs_flags_query_without_a_reply_field(self):
        command_set = catalog_command_set("remoteLinc2")
        extended_value(command_set, "configuration")["name"] = "operatingFlags"

        self.assertEqual(problems(command_set), ["the operatingFlags value holds the operating flags byte, so it needs flagsQuery"])


class GuardedNameVariantTests(unittest.TestCase):
    def test_a_flag_named_powerline_off_needs_guard_keep(self):
        command_set = catalog_command_set("globalLine")
        del renamed(command_set, "operatingFlags", "powerLineOff", "powerlineOff")["guard"]

        self.assertEqual(problems(command_set), ["the powerlineOff flag needs guard 'keep'"])

    def test_a_flag_named_checksum_required_on_needs_guard_keep(self):
        command_set = catalog_command_set("globalLine")
        del renamed(command_set, "operatingFlags", "checksumRequired", "checksumRequiredOn")["guard"]

        self.assertEqual(problems(command_set), ["the checksumRequiredOn flag needs guard 'keep'"])

    def test_a_command_named_powerline_off_needs_guard_never(self):
        command_set = catalog_command_set("outdoorApplianceLinc")
        del renamed(command_set, "flagCommands", "powerLineOff", "powerlineOff")["guard"]

        self.assertEqual(problems(command_set), ["the powerlineOff command turns a guarded flag on, so it needs guard 'never'"])

    def test_a_command_named_checksum_required_on_needs_guard_never(self):
        command_set = catalog_command_set("outdoorApplianceLinc")
        del renamed(command_set, "flagCommands", "checksumOn", "checksumRequiredOn")["guard"]

        self.assertEqual(problems(command_set), ["the checksumRequiredOn command turns a guarded flag on, so it needs guard 'never'"])


class StateHoldingTests(unittest.TestCase):
    def test_a_relay_no_flag_releases_always_holds_its_state(self):
        command_set = io_linc_with({"releasedBy": [], "restState": "off"})

        self.assertEqual(problems(command_set), [])

    def test_a_relay_no_flag_releases_cannot_pulse_on_every_command(self):
        command_set = io_linc_with({"releasedBy": [], "restState": "off", "pulsesOnEveryCommandWhen": [["momentary"]]})

        self.assertEqual(problems(command_set), ["the relay group type's stateHolding has pulsesOnEveryCommandWhen, but no releasedBy flag releases the relay"])


if __name__ == "__main__":
    unittest.main()
