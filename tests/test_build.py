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
PROFILE_VALIDATOR = jsonschema.Draft202012Validator(json.loads((build.ROOT / "schema" / "device-profile.schema.json").read_text()))


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


def catalog_profile(model):
    """A copy of one of the catalog's device profiles, to change in a test."""
    return copy.deepcopy(json.loads((build.ROOT / "devices" / f"{model}.json").read_text()))


def command(command_set, name):
    """The command set's flag, standard or extended command called name."""
    return next(item for key in ("flagCommands", "standardCommands", "extendedCommands") for item in command_set.get(key, []) if item["name"] == name)


def extended_value(command_set, name):
    """The command set's extended settings value called name."""
    return next(value for value in command_set["extendedSettings"]["values"] if value["name"] == name)


class CatalogTests(unittest.TestCase):
    def test_every_command_set_in_the_catalog_passes(self):
        for path in sorted((build.ROOT / "commandSets").glob("*.json")):
            with self.subTest(command_set=path.stem):
                self.assertEqual(problems(json.loads(path.read_text())), [])


class EffectSchemaTests(unittest.TestCase):
    def test_a_flag_command_without_an_effect_fails_the_schema(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "yakityYakOff").pop("effect", None)

        self.assertEqual(problems(command_set), ["'effect' is a required property"])

    def test_a_standard_command_without_idempotent_fails_the_schema(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "lightOn").pop("idempotent", None)

        self.assertEqual(problems(command_set), ["'idempotent' is a required property"])

    def test_an_extended_command_with_an_effect_the_schema_does_not_name_fails(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "triggerGroup")["effect"] = "sideEffect"

        self.assertEqual(problems(command_set), ["'sideEffect' is not one of ['readOnly', 'configuration', 'link', 'actuation', 'destructive']"])

    def test_a_raw_keep_awake_message_without_an_effect_fails_the_schema(self):
        profile = catalog_profile("2441ZTH")
        profile["lifecycle"]["fromHub"]["keepAwake"]["send"].pop("effect", None)

        self.assertFalse(PROFILE_VALIDATOR.is_valid(profile))

    def test_a_raw_keep_awake_message_without_idempotent_fails_the_schema(self):
        profile = catalog_profile("2441ZTH")
        profile["lifecycle"]["fromHub"]["keepAwake"]["release"].pop("idempotent", None)

        self.assertFalse(PROFILE_VALIDATOR.is_valid(profile))

    def test_a_named_keep_awake_message_carries_no_effect_of_its_own(self):
        profile = catalog_profile("2852")
        profile["lifecycle"]["fromHub"]["keepAwake"]["send"]["effect"] = "configuration"

        self.assertFalse(PROFILE_VALIDATOR.is_valid(profile))


class EffectRuleTests(unittest.TestCase):
    def test_a_command_never_sent_must_be_destructive(self):
        command_set = catalog_command_set("outdoorApplianceLinc")
        command(command_set, "radioOff")["effect"] = "configuration"

        self.assertEqual(problems(command_set), ["the radioOff command is never sent, so its effect must be destructive"])

    def test_a_flag_command_is_never_read_only(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "yakityYakOff")["effect"] = "readOnly"

        self.assertEqual(problems(command_set), ["the yakityYakOff command is Set Operating Flags, which is never readOnly"])

    def test_an_extended_command_with_cmd1_0x20_is_never_read_only(self):
        command_set = catalog_command_set("tempLinc")
        command(command_set, "beepOn")["effect"] = "readOnly"

        self.assertEqual(problems(command_set), ["the beepOn command is Set Operating Flags, which is never readOnly"])

    def test_an_extended_set_is_never_read_only(self):
        command_set = catalog_command_set("hiddenDoorSensor")
        command(command_set, "setHeartbeatInterval")["effect"] = "readOnly"

        self.assertEqual(problems(command_set), ["the setHeartbeatInterval command is an extended Set, which is never readOnly"])

    def test_an_extended_get_may_be_read_only(self):
        command_set = catalog_command_set("hiddenDoorSensor")

        self.assertEqual(command(command_set, "readSettings")["effect"], "readOnly")
        self.assertEqual(problems(command_set), [])

    def test_a_read_only_command_must_be_idempotent(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "readStatus")["idempotent"] = False

        self.assertEqual(problems(command_set), ["the readStatus command is readOnly, so it must be idempotent"])

    def test_a_command_an_action_names_must_be_actuation(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "lightOn")["effect"] = "configuration"

        self.assertEqual(problems(command_set), [
            "the light group type's on action names 'lightOn', which isn't actuation",
            "the load group type's on action names 'lightOn', which isn't actuation",
        ])

    def test_a_command_a_group_type_reads_its_state_with_must_be_read_only(self):
        command_set = catalog_command_set("globalLine")
        command(command_set, "readStatus")["effect"] = "actuation"

        self.assertEqual(problems(command_set), [
            "the light group type reads its state with 'readStatus', which isn't readOnly",
            "the load group type reads its state with 'readStatus', which isn't readOnly",
        ])

    def test_a_flag_on_command_must_be_configuration(self):
        command_set = catalog_command_set("i3Dial")
        command(command_set, "nightModeOn")["effect"] = "actuation"

        self.assertEqual(problems(command_set), ["the nightMode flag's onCommand names 'nightModeOn', which isn't configuration"])

    def test_a_value_write_command_must_be_configuration(self):
        command_set = catalog_command_set("ledBulb")
        command(command_set, "writeRampRate")["effect"] = "destructive"

        self.assertEqual(problems(command_set), ["the rampRate value is written by 'writeRampRate', which isn't configuration"])

    def test_a_named_keep_awake_command_must_be_idempotent(self):
        command_set = catalog_command_set("openCloseSensor")
        command(command_set, "stayAwake")["idempotent"] = False

        self.assertEqual(build.from_hub_command_set_problems(catalog_profile("2843"), {"openCloseSensor": command_set}), [
            "fromHub keepAwake send names 'stayAwake', which isn't configuration and idempotent in openCloseSensor",
        ])

    def test_a_named_keep_awake_command_must_be_configuration(self):
        command_set = catalog_command_set("openCloseSensor")
        command(command_set, "stayAwake")["effect"] = "actuation"

        self.assertEqual(build.from_hub_command_set_problems(catalog_profile("2843"), {"openCloseSensor": command_set}), [
            "fromHub keepAwake send names 'stayAwake', which isn't configuration and idempotent in openCloseSensor",
        ])

    def test_a_raw_keep_awake_message_must_be_configuration_and_idempotent(self):
        profile = catalog_profile("2441ZTH")
        profile["lifecycle"]["fromHub"]["keepAwake"]["send"]["effect"] = "actuation"
        profile["lifecycle"]["fromHub"]["keepAwake"]["release"]["idempotent"] = False

        self.assertEqual(build.from_hub_problems(profile), [
            "fromHub keepAwake send must be configuration and idempotent",
            "fromHub keepAwake release must be configuration and idempotent",
        ])

    def test_a_flag_command_and_an_extended_set_operating_flags_command_with_one_cmd2_need_one_effect(self):
        command_set = catalog_command_set("globalLine")
        command_set["extendedCommands"].append({
            "name": "yakityYakOffNow", "description": "Turns the Yakity Yak signaling option off.",
            "effect": "actuation", "idempotent": True, "command1": "0x20", "command2": "0x26",
        })

        self.assertEqual(problems(command_set), ["the yakityYakOff command and the yakityYakOffNow command both send Set Operating Flags with cmd2 0x26, so they need the same effect"])

    def test_a_flag_and_a_standard_set_operating_flags_command_with_one_cmd2_need_one_effect(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "keyBeepNow", "description": "Turns the key beep on.",
            "effect": "actuation", "idempotent": True, "command1": "0x20", "command2": "0x0A",
        })

        self.assertEqual(problems(command_set), ["the keyBeep flag and the keyBeepNow command both send Set Operating Flags with cmd2 0x0A, so they need the same effect"])

    def test_set_operating_flags_entries_with_one_cmd2_and_one_effect_pass(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "keyBeepAgain", "description": "Turns the key beep on.",
            "effect": "configuration", "idempotent": True, "command1": "0x20", "command2": "0x0A",
        })

        self.assertEqual(problems(command_set), [])

    def test_a_destructive_command_that_turns_a_guarded_flag_on_needs_guard_never_too(self):
        command_set = catalog_command_set("outdoorApplianceLinc")
        del command(command_set, "radioOff")["guard"]

        self.assertEqual(command(command_set, "radioOff")["effect"], "destructive")
        self.assertEqual(problems(command_set), ["the radioOff command turns a guarded flag on, so it needs guard 'never'"])


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


class KeptFlagDefaultTests(unittest.TestCase):
    def test_a_kept_flag_needs_a_default(self):
        command_set = catalog_command_set("globalLine")
        del next(flag for flag in command_set["operatingFlags"] if flag["name"] == "radioOff")["default"]

        self.assertEqual(problems(command_set), ["the radioOff flag is kept, so it needs a default"])

    def test_a_kept_flag_under_a_variant_name_needs_a_default(self):
        command_set = catalog_command_set("globalLine")
        del renamed(command_set, "operatingFlags", "checksumRequired", "checksumRequiredOn")["default"]

        self.assertEqual(problems(command_set), ["the checksumRequiredOn flag is kept, so it needs a default"])


class StateHoldingTests(unittest.TestCase):
    def test_a_relay_no_flag_releases_always_holds_its_state(self):
        command_set = io_linc_with({"releasedBy": [], "restState": "off"})

        self.assertEqual(problems(command_set), [])

    def test_a_relay_no_flag_releases_cannot_pulse_on_every_command(self):
        command_set = io_linc_with({"releasedBy": [], "restState": "off", "pulsesOnEveryCommandWhen": [["momentary"]]})

        self.assertEqual(problems(command_set), ["the relay group type's stateHolding has pulsesOnEveryCommandWhen, but no releasedBy flag releases the relay"])


if __name__ == "__main__":
    unittest.main()
