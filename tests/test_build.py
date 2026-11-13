"""Tests for the checks scripts/build.py makes beyond what the schemas say.

Run from the repository's root: python3 -I -m unittest discover -s tests
"""

import collections
import copy
import html.parser
import json
import pathlib
import re
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

        self.assertEqual(problems(command_set), ["the yakityYakOff command and the yakityYakOffNow command both send Set Operating Flags with cmd2 0x26, so they need the same effect and idempotent"])

    def test_a_flag_and_a_standard_set_operating_flags_command_with_one_cmd2_need_one_effect(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "keyBeepNow", "description": "Turns the key beep on.",
            "effect": "actuation", "idempotent": True, "command1": "0x20", "command2": "0x0A",
        })

        self.assertEqual(problems(command_set), ["the keyBeep flag and the keyBeepNow command both send Set Operating Flags with cmd2 0x0A, so they need the same effect and idempotent"])

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


class EffectRuleGapTests(unittest.TestCase):
    def test_a_standard_command_never_sent_must_be_destructive(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "exampleLockOn", "description": "Locks the device.", "effect": "configuration", "idempotent": True,
            "command1": "0x20", "command2": "0x7F", "guard": "never",
        })

        self.assertEqual(problems(command_set), ["the exampleLockOn command is never sent, so its effect must be destructive"])

    def test_an_extended_command_never_sent_must_be_destructive(self):
        command_set = catalog_command_set("tempLinc")
        command(command_set, "programmingLockOn")["effect"] = "configuration"

        self.assertEqual(problems(command_set), ["the programmingLockOn command is never sent, so its effect must be destructive"])

    def test_a_standard_command_with_cmd1_0x20_is_never_read_only(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "exampleFlagOn", "description": "Sets a flag.", "effect": "readOnly", "idempotent": True,
            "command1": "0x20", "command2": "0x7F",
        })

        self.assertEqual(problems(command_set), ["the exampleFlagOn command is Set Operating Flags, which is never readOnly"])

    def test_a_properties_write_is_never_read_only(self):
        command_set = catalog_command_set("i3Dial")
        command(command_set, "writeProperties")["effect"] = "readOnly"

        self.assertEqual(problems(command_set), ["the writeProperties command writes properties (cmd1 0x2E, cmd2 0x01, D1 0x02), which is never readOnly"])

    def test_a_cmd1_0x2f_write_is_never_read_only(self):
        command_set = catalog_command_set("energyDisplay")
        command(command_set, "writeMeterId")["effect"] = "readOnly"

        self.assertEqual(problems(command_set), ["the writeMeterId command writes with cmd1 0x2F and D2 0x02, which is never readOnly"])

    def test_an_extended_set_whose_selector_is_a_parameter_is_never_read_only(self):
        command_set = catalog_command_set("hiddenDoorSensor")
        write = command(command_set, "setHeartbeatInterval")
        write["effect"] = "readOnly"
        write["fixed"] = [{"position": 1, "value": "0x02"}]
        write["parameters"].append({"name": "selector", "description": "The setting to write.", "byte": 2})

        self.assertEqual(problems(command_set), ["the setHeartbeatInterval command is an extended Set, which is never readOnly"])

    def test_a_parameterized_set_operating_flags_command_needs_the_effect_of_every_flag_it_can_send(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "anyFlag", "description": "Sends any Set Operating Flags cmd2.", "effect": "actuation", "idempotent": True,
            "command1": "0x20", "parameter": {"name": "cmd2", "description": "The cmd2."},
        })

        self.assertIn("the yakityYakOff command and the anyFlag command both send Set Operating Flags with cmd2 0x26, so they need the same effect and idempotent", problems(command_set))
        self.assertIn("the keyBeep flag and the anyFlag command both send Set Operating Flags with cmd2 0x0A, 0x0B, so they need the same effect and idempotent", problems(command_set))

    def test_set_operating_flags_entries_with_one_cmd2_need_one_idempotent(self):
        command_set = catalog_command_set("globalLine")
        command_set["standardCommands"].append({
            "name": "keyBeepToggle", "description": "Turns the key beep on.", "effect": "configuration", "idempotent": False,
            "command1": "0x20", "command2": "0x0A",
        })

        self.assertEqual(problems(command_set), ["the keyBeep flag and the keyBeepToggle command both send Set Operating Flags with cmd2 0x0A, so they need the same effect and idempotent"])

    def test_extended_commands_one_message_can_match_need_one_effect_and_idempotent(self):
        command_set = catalog_command_set("tempLinc")
        command_set["extendedCommands"].append({
            "name": "writePage", "description": "Writes a page of settings.", "effect": "configuration", "idempotent": True,
            "command1": "0x2E", "command2": "0x00", "fixed": [{"position": 1, "value": "0x01"}],
            "parameters": [{"name": "page", "description": "The page.", "byte": 3}], "integrity": "checksum",
        })

        self.assertEqual(problems(command_set), [
            "the readSettings command and the writePage command can match the same extended message, so they need the same effect and idempotent",
            "the readMoreSettings command and the writePage command can match the same extended message, so they need the same effect and idempotent",
        ])

    def test_an_unfixed_byte_must_be_0x00_so_differing_fixed_bytes_do_not_overlap(self):
        command_set = catalog_command_set("energyDisplay")

        self.assertEqual(command(command_set, "readMeterIds")["effect"], "readOnly")
        self.assertEqual(problems(command_set), [])

    def test_a_read_only_extended_command_may_not_match_every_message_a_write_does(self):
        command_set = catalog_command_set("globalLine")
        command_set["extendedCommands"] += [
            {"name": "readThing", "description": "Reads a thing.", "effect": "readOnly", "idempotent": True,
             "command1": "0x50", "command2": "0x00", "parameters": [{"name": "thing", "description": "The thing.", "byte": 1}]},
            {"name": "writeThing", "description": "Writes a thing.", "effect": "configuration", "idempotent": True,
             "command1": "0x50", "command2": "0x00", "fixed": [{"position": 1, "value": "0x01"}]},
        ]

        self.assertEqual(problems(command_set), ["the readThing command is readOnly, but it matches every message the writeThing command does"])

    def test_a_keep_awake_flag_needs_no_effect_of_its_own(self):
        profile = catalog_profile("2444A2WH4")

        self.assertEqual(profile["lifecycle"]["fromHub"]["keepAwake"]["send"], {"flag": "stayAwake", "set": True})
        self.assertEqual(build.from_hub_command_set_problems(profile, {"remoteLinc2": catalog_command_set("remoteLinc2")}), [])

    def test_raw_keep_awake_bytes_need_the_effect_of_the_command_set_entry_with_those_bytes(self):
        command_set = catalog_command_set("tempLinc")
        command(command_set, "setDisplayCelsius")["effect"] = "actuation"

        self.assertEqual(build.from_hub_command_set_problems(catalog_profile("2441ZTH"), {"tempLinc": command_set}), [
            "fromHub keepAwake send has the bytes of tempLinc's setDisplayCelsius, so it needs the same effect and idempotent",
        ])


def serial_command_set():
    """An invented command set with serial commands, to change in a test."""
    return {
        "id": "invented", "name": "Invented", "description": "An invented modem.", "sources": ["An invented guide"],
        "serialCommands": [
            {"name": "readInfo", "description": "Asks for the identity.", "effect": "readOnly", "idempotent": True, "number": "0x60",
             "reply": [{"name": "identity", "description": "The identity.", "bytes": [1, 2, 3]}]},
            {"name": "startThing", "description": "Starts a thing.", "effect": "link", "idempotent": False, "number": "0x64",
             "fixed": [{"position": 1, "value": "0x01"}], "parameters": [{"name": "group", "description": "The group.", "byte": 2}]},
            {"name": "deleteThing", "description": "Deletes a thing.", "effect": "destructive", "idempotent": True, "number": "0x64",
             "fixed": [{"position": 1, "value": "0xFF"}], "parameters": [{"name": "group", "description": "The group.", "byte": 2}]},
        ],
    }


def serial_command(command_set, name):
    """The command set's serial command called name."""
    return next(item for item in command_set["serialCommands"] if item["name"] == name)


class SerialCommandSchemaTests(unittest.TestCase):
    def test_a_serial_command_set_passes(self):
        self.assertEqual(problems(serial_command_set()), [])

    def test_a_serial_command_without_an_effect_fails_the_schema(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo").pop("effect")

        self.assertEqual(problems(command_set), ["'effect' is a required property"])

    def test_a_serial_command_without_idempotent_fails_the_schema(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo").pop("idempotent")

        self.assertEqual(problems(command_set), ["'idempotent' is a required property"])

    def test_a_serial_command_without_a_number_fails_the_schema(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo").pop("number")

        self.assertEqual(problems(command_set), ["'number' is a required property"])

    def test_a_serial_command_with_an_effect_the_schema_does_not_name_fails(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo")["effect"] = "sideEffect"

        self.assertEqual(problems(command_set), ["'sideEffect' is not one of ['readOnly', 'configuration', 'link', 'actuation', 'destructive']"])

    def test_a_serial_command_has_no_cmd1(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo")["command1"] = "0x11"

        self.assertEqual(problems(command_set), ["Additional properties are not allowed ('command1' was unexpected)"])


class SerialCommandRuleTests(unittest.TestCase):
    def test_a_serial_command_never_sent_must_be_destructive(self):
        command_set = serial_command_set()
        serial_command(command_set, "startThing")["guard"] = "never"

        self.assertEqual(problems(command_set), ["the startThing serial command is never sent, so its effect must be destructive"])

    def test_a_read_only_serial_command_must_be_idempotent(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo")["idempotent"] = False

        self.assertEqual(problems(command_set), ["the readInfo serial command is readOnly, so it must be idempotent"])

    def test_a_serial_command_that_carries_a_device_message_is_not_an_entry(self):
        for number in ("0x61", "0x62"):
            with self.subTest(number=number):
                command_set = serial_command_set()
                serial_command(command_set, "readInfo")["number"] = number

                self.assertEqual(problems(command_set), [f"the readInfo serial command has number {number}, which carries a device message and so isn't an entry"])

    def test_serial_commands_with_one_number_and_different_fixed_bytes_need_not_share_an_effect(self):
        self.assertEqual(problems(serial_command_set()), [])

    def test_serial_commands_that_send_the_same_number_and_fixed_bytes_fail(self):
        command_set = serial_command_set()
        serial_command(command_set, "deleteThing")["fixed"] = [{"position": 1, "value": "0x01"}]

        self.assertEqual(problems(command_set), [
            "two serial commands send the same number and fixed bytes",
            "the startThing serial command and the deleteThing serial command can match the same frame, so they need the same effect and idempotent",
        ])

    def test_serial_commands_one_frame_can_match_need_one_effect_and_idempotent(self):
        command_set = serial_command_set()
        command_set["serialCommands"].append({
            "name": "anyThing", "description": "Does a thing with any control byte.", "effect": "configuration", "idempotent": True, "number": "0x64",
            "parameters": [{"name": "control", "description": "The control byte.", "byte": 1}, {"name": "group", "description": "The group.", "byte": 2}],
        })

        self.assertEqual(problems(command_set), [
            "the startThing serial command and the anyThing serial command can match the same frame, so they need the same effect and idempotent",
            "the deleteThing serial command and the anyThing serial command can match the same frame, so they need the same effect and idempotent",
        ])

    def test_a_read_only_serial_command_may_not_match_every_frame_a_write_does(self):
        command_set = serial_command_set()
        command_set["serialCommands"] += [
            {"name": "readAny", "description": "Reads any.", "effect": "readOnly", "idempotent": True, "number": "0x6F",
             "parameters": [{"name": "control", "description": "The control byte.", "byte": 1}]},
            {"name": "writeOne", "description": "Writes one.", "effect": "destructive", "idempotent": True, "number": "0x6F",
             "fixed": [{"position": 1, "value": "0x80"}]},
        ]

        self.assertEqual(problems(command_set), ["the readAny serial command is readOnly, but it matches every frame the writeOne serial command does"])

    def test_serial_commands_with_one_number_need_one_payload_length(self):
        command_set = serial_command_set()
        serial_command(command_set, "deleteThing")["parameters"] = []

        self.assertEqual(problems(command_set), ["the startThing and deleteThing serial commands share number 0x64 but differ in payload length"])

    def test_a_payload_byte_must_be_fixed_or_a_parameter(self):
        command_set = serial_command_set()
        serial_command(command_set, "startThing")["fixed"] = []
        serial_command(command_set, "deleteThing")["fixed"] = []
        serial_command(command_set, "deleteThing")["number"] = "0x65"

        self.assertEqual(problems(command_set), ["the startThing serial command: payload byte 1 is neither fixed nor a parameter", "the deleteThing serial command: payload byte 1 is neither fixed nor a parameter"])

    def test_a_payload_byte_is_filled_once(self):
        command_set = serial_command_set()
        serial_command(command_set, "startThing")["parameters"][0]["byte"] = 1

        self.assertEqual(problems(command_set), [
            "the startThing serial command: it fills a payload byte twice",
            "the startThing and deleteThing serial commands share number 0x64 but differ in payload length",
        ])

    def test_a_reply_reads_a_payload_byte_once(self):
        command_set = serial_command_set()
        serial_command(command_set, "readInfo")["reply"].append({"name": "again", "description": "Again.", "byte": 2})

        self.assertEqual(problems(command_set), ["the readInfo serial command's reply reads a payload byte twice"])

    def test_a_serial_command_value_names_a_payload_byte(self):
        command_set = serial_command_set()
        del serial_command(command_set, "startThing")["parameters"][0]["byte"]

        self.assertEqual(problems(command_set), [
            "the startThing serial command: the group value needs a byte or bytes",
            "the startThing and deleteThing serial commands share number 0x64 but differ in payload length",
        ])

    def test_a_serial_command_name_is_not_used_twice(self):
        command_set = serial_command_set()
        command_set["standardCommands"] = [{"name": "readInfo", "description": "A clash.", "effect": "readOnly", "idempotent": True, "command1": "0x19"}]

        self.assertEqual(problems(command_set), ["a command or message name appears more than once"])


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


def marked_statuses(value):
    """Every verification status in value, found by reading the JSON independently of the build."""
    found = []

    def visit(node, key=None):
        if isinstance(node, dict):
            if key == "verification" and "status" in node:
                found.append(node["status"])
            for child_key, child in node.items():
                visit(child, child_key)
        elif isinstance(node, list):
            for child in node:
                visit(child, key)

    visit(value)

    return found


class PageParser(html.parser.HTMLParser):
    """Reads the page's coverage numbers, links, scripts and headings."""

    def __init__(self):
        super().__init__()
        self.metrics = {}
        self.sources = []
        self.hrefs = []
        self.headings = []
        self.landmarks = set()
        self._metric = None
        self._heading = None

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        self.sources += [attributes[name] for name in ("src", "srcset") if name in attributes]

        if tag == "link" and "href" in attributes:
            self.sources.append(attributes["href"])
        if tag == "a":
            self.hrefs.append(attributes.get("href", ""))
        if tag in ("header", "main", "footer", "nav"):
            self.landmarks.add(tag)
        if "data-metric" in attributes:
            self._metric = attributes["data-metric"]
        if tag in ("h1", "h2", "h3"):
            self._heading = tag
            self.headings.append([tag, ""])

    def handle_endtag(self, tag):
        self._metric = None
        self._heading = None

    def handle_data(self, data):
        if self._metric:
            self.metrics[self._metric] = self.metrics.get(self._metric, "") + data
        if self._heading:
            self.headings[-1][1] += data


def catalog_page():
    profiles, _ = build.load_profiles()
    command_sets, _ = build.load_command_sets(profiles)
    page = build.index_page(profiles, command_sets, "0.0.0")
    parser = PageParser()
    parser.feed(page)

    return profiles, command_sets, page, parser


class CoverageTests(unittest.TestCase):
    def test_counts_profiles_identities_and_identity_statuses(self):
        profiles = [
            {"identities": [{}, {"verification": {"status": "observed", "note": "n"}}], "commandSets": []},
            {"identities": [{"verification": {"status": "conflicting", "note": "n"}}]},
        ]
        coverage = build.coverage(profiles, [])

        self.assertEqual(coverage["profiles"], 2)
        self.assertEqual(coverage["identities"], 3)
        self.assertEqual(coverage["identityStatuses"], {"observed": 1, "documented": 1, "inferred": 0, "conflicting": 1})

    def test_separates_described_deliberately_empty_and_undescribed_profiles(self):
        command_sets = [
            {"id": "described", "name": "D", "operatingFlags": []},
            {"id": "empty", "name": "E", "description": "Nothing to read.", "sources": ["S"]},
        ]
        profiles = [
            {"identities": [{}], "commandSets": [{"commandSet": "described"}]},
            {"identities": [{}], "commandSets": [{"commandSet": "empty"}]},
            {"identities": [{}], "commandSets": [{"commandSet": "empty"}, {"commandSet": "described"}]},
            {"identities": [{}]},
        ]
        coverage = build.coverage(profiles, command_sets)

        self.assertEqual(coverage["described"], 2)
        self.assertEqual(coverage["deliberatelyEmpty"], 1)
        self.assertEqual(coverage["undescribed"], 1)

    def test_counts_the_status_of_every_marked_command_set_value(self):
        command_sets = [{"id": "a", "name": "A", "operatingFlags": [
            {"verification": {"status": "inferred", "note": "n"}},
            {"nested": [{"verification": {"status": "inferred", "note": "n"}}, {"verification": {"status": "observed", "note": "n"}}]},
        ]}]
        coverage = build.coverage([], command_sets)

        self.assertEqual(coverage["commandSetStatuses"], {"observed": 1, "documented": 0, "inferred": 2, "conflicting": 0})

    def test_matches_the_catalog_files(self):
        profiles, command_sets, _, _ = catalog_page()
        coverage = build.coverage(profiles, command_sets)
        expected = collections.Counter(status for command_set in command_sets for status in marked_statuses(command_set))

        self.assertEqual(coverage["commandSetStatuses"], {status: expected[status] for status in build.STATUSES})
        self.assertEqual(coverage["described"] + coverage["deliberatelyEmpty"] + coverage["undescribed"], len(profiles))
        self.assertEqual(sum(coverage["identityStatuses"].values()), coverage["identities"])


class CardParser(html.parser.HTMLParser):
    """Reads each card's model, its filter attributes and the facts in its detail section."""

    def __init__(self):
        super().__init__()
        self.cards = {}
        self._card = None
        self._command_set = None
        self._fact = None
        self._depth = 0
        self._in_details = False
        self._summary = False

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)

        if tag == "article":
            self._card = {"attributes": attributes, "facts": [], "details": False, "summary": "", "outside": ""}
            self.cards[attributes["data-model"]] = self._card
        elif self._card is not None:
            if tag == "details":
                self._in_details = True
                self._card["details"] = True
            if tag == "summary":
                self._summary = True
            if "data-command-set" in attributes:
                self._command_set = attributes["data-command-set"]
            if "data-fact" in attributes:
                self._fact = [self._command_set, attributes["data-fact"], ""]
                self._card["facts"].append(self._fact)

    def handle_endtag(self, tag):
        if tag == "article":
            self._card = None
            self._command_set = None
            self._in_details = False
        elif tag in ("p", "li") and self._fact is not None:
            self._fact = None
        elif tag == "details":
            self._in_details = False
        elif tag == "summary":
            self._summary = False

    def handle_data(self, data):
        if self._card is None:
            return
        if self._fact is not None:
            self._fact[2] += data
        if self._summary:
            self._card["summary"] += data
        if not self._in_details:
            self._card["outside"] += data


def facts(card, name, command_set=None):
    return [text.strip() for owner, fact, text in card["facts"] if fact == name and (command_set is None or owner == command_set)]


def read_cards(page):
    parser = CardParser()
    parser.feed(page)

    return parser.cards


def disk_json(folder, name):
    return json.loads((build.ROOT / folder / f"{name}.json").read_text())


def page_text(page):
    text = re.sub(r"<(script|style)\b.*?</\1>", "", page, flags=re.S)

    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text))


class CapabilityLegendTests(unittest.TestCase):
    def setUp(self):
        self.profiles, self.command_sets, self.page, self.parser = catalog_page()
        self.metrics = {key: int(value.strip()) for key, value in self.parser.metrics.items()}
        self.schema = json.loads((build.ROOT / "schema" / "device-profile.schema.json").read_text())

    def test_each_capability_count_is_the_number_of_profiles_that_have_it(self):
        kinds = [option["properties"]["kind"]["const"] for option in self.schema["$defs"]["capability"]["oneOf"]]

        self.assertEqual(sorted(kinds), sorted(build.CAPABILITY_EXPLANATIONS))

        for kind in kinds:
            expected = sum(any(c["kind"] == kind for c in profile["capabilities"]) for profile in self.profiles)
            self.assertEqual(self.metrics[f"capability-{kind}"], expected, kind)

    def test_each_radio_count_is_the_number_of_profiles_that_state_it(self):
        for radio in ("powerline", "rf", "dual"):
            expected = sum(profile.get("radio") == radio for profile in self.profiles)
            self.assertEqual(self.metrics[f"radio-{radio}"], expected, radio)

        self.assertEqual(self.metrics["radio-unstated"], sum("radio" not in profile for profile in self.profiles))

    def test_the_battery_count_is_the_number_of_battery_powered_profiles(self):
        self.assertEqual(self.metrics["battery"], sum(profile.get("batteryPowered", False) for profile in self.profiles))

    def test_each_engine_count_is_the_number_of_profiles_with_an_entry_for_it(self):
        for engine in ("i1", "i2", "i2cs"):
            expected = sum(any(entry["engine"] == engine for entry in profile.get("engines", [])) for profile in self.profiles)
            self.assertEqual(self.metrics[f"engine-{engine}"], expected, engine)

    def test_every_term_has_one_plain_sentence(self):
        explanations = [*build.CAPABILITY_EXPLANATIONS.values(), *build.RADIO_EXPLANATIONS.values(), *build.ENGINE_EXPLANATIONS.values(), build.BATTERY_EXPLANATION]

        for sentence in explanations:
            self.assertTrue(sentence.endswith("."), sentence)
            self.assertEqual(sentence.count("."), 1, sentence)
            self.assertIn(html.escape(sentence), self.page)

    def test_the_legend_is_a_labeled_section_listed_in_the_page_links(self):
        self.assertIn("#capabilities-heading", self.parser.hrefs)
        self.assertIn("What the filters mean", [text for _, text in self.parser.headings])
        self.assertIn('aria-labelledby="capabilities-heading"', self.page)


class CapabilityDetailTests(unittest.TestCase):
    def setUp(self):
        self.profiles, self.command_sets, self.page, _ = catalog_page()
        self.cards = read_cards(self.page)

    def test_every_profile_has_a_card_with_an_expandable_detail(self):
        self.assertEqual(sorted(self.cards), sorted(profile["model"] for profile in self.profiles))

        for card in self.cards.values():
            self.assertTrue(card["details"])
            self.assertIn("What the catalog describes", card["summary"])

    def test_the_first_lines_of_a_card_carry_no_counts(self):
        for card in self.cards.values():
            self.assertNotRegex(card["outside"], r"\boperating flags?\b|\bextended settings?\b|\bstandard commands?\b|\bserial commands?\b")

    def test_a_command_set_s_counts_and_labels_are_the_data_s(self):
        for profile in self.profiles:
            card = self.cards[profile["model"]]

            for set_id in dict.fromkeys(entry["commandSet"] for entry in profile.get("commandSets", [])):
                command_set = disk_json("commandSets", set_id)
                flags = command_set.get("operatingFlags", [])
                settings = (command_set.get("extendedSettings") or {}).get("values", [])

                for name, items in (("operatingFlags", flags), ("extendedSettings", settings)):
                    found = facts(card, name, set_id)

                    if not items:
                        self.assertEqual(found, [], (profile["model"], name))
                        continue

                    self.assertEqual(len(found), 1, (profile["model"], name))
                    self.assertRegex(found[0], rf"^{len(items)} ")

                    for item in items:
                        self.assertIn(item["label"], found[0])

                for name, key in (("standardCommands", "standardCommands"), ("extendedCommands", "extendedCommands"), ("serialCommands", "serialCommands"), ("readings", "readings")):
                    found = facts(card, name, set_id)
                    items = command_set.get(key, [])

                    if items:
                        self.assertEqual(len(found), 1, (profile["model"], name))
                        self.assertRegex(found[0], rf"^{len(items)} ")
                    else:
                        self.assertEqual(found, [], (profile["model"], name))

    def test_a_modem_reports_its_serial_commands(self):
        card = self.cards["2413U"]
        entries = catalog_profile("2413U")["commandSets"]

        for entry in entries:
            expected = len(disk_json("commandSets", entry["commandSet"]).get("serialCommands", []))
            self.assertRegex(facts(card, "serialCommands", entry["commandSet"])[0], rf"^{expected} serial commands")

    def test_a_profile_with_no_command_set_says_so_and_implies_no_capability(self):
        missing = [profile for profile in self.profiles if not profile.get("commandSets")]
        self.assertTrue(missing)

        for profile in missing:
            card = self.cards[profile["model"]]

            self.assertEqual(facts(card, "noCommandSet"), ["The catalog has no command set for this device."], profile["model"])
            self.assertEqual([fact for _, fact, _ in card["facts"] if fact in build.COMMAND_SET_FACTS], [], profile["model"])

    def test_a_profile_deliberately_without_settings_says_so(self):
        empty = [p for p in self.profiles if p.get("commandSets") and all(not (set(disk_json("commandSets", e["commandSet"])) - build.COMMAND_SET_DESCRIPTIVE_KEYS) for e in p["commandSets"])]
        self.assertTrue(empty)

        for profile in empty:
            card = self.cards[profile["model"]]

            self.assertEqual(facts(card, "noSettings"), ["The catalog deliberately holds no settings for this device: there is nothing for software to read or write."], profile["model"])
            self.assertEqual(facts(card, "noCommandSet"), [])
            self.assertEqual([fact for _, fact, _ in card["facts"] if fact in build.COMMAND_SET_FACTS], [], profile["model"])

    def test_radio_role_battery_and_engine_follow_the_profile(self):
        radios = {"powerline": "Powerline", "rf": "RF", "dual": "Dual-band"}

        for profile in self.profiles:
            card = self.cards[profile["model"]]
            radio = facts(card, "radio")
            engine = facts(card, "engine")

            self.assertEqual(len(radio), 1)
            self.assertIn(radios[profile["radio"]] if "radio" in profile else "does not state", radio[0], profile["model"])
            self.assertEqual(bool(facts(card, "battery")), bool(profile.get("batteryPowered")), profile["model"])
            self.assertEqual(len(engine), 1)

            if profile.get("engines"):
                for entry in profile["engines"]:
                    self.assertIn(build.ENGINE_LABELS[entry["engine"]], engine[0])
            else:
                self.assertIn("does not state", engine[0])

    def test_groups_events_and_heartbeat_follow_the_profile(self):
        for profile in self.profiles:
            card = self.cards[profile["model"]]
            groups = facts(card, "groups")

            self.assertEqual(len(groups), 1, profile["model"])

            for group in profile.get("groups", []):
                self.assertIn(group["name"], groups[0], profile["model"])

            if not profile.get("groups"):
                self.assertIn("lists no ALL-Link groups", groups[0])

            for capability in profile["capabilities"]:
                if capability["kind"] == "groupEvents":
                    text = " ".join(facts(card, "events"))
                    self.assertTrue(text, profile["model"])

                    for event in capability["events"]:
                        self.assertIn(event["event"], text)
                        self.assertIn(event["command1"], text)

                if capability["kind"] == "heartbeat":
                    text = " ".join(facts(card, "heartbeat"))
                    self.assertIn(f"group {int(capability['group'], 16)}", text)

                    if "intervalMinutes" in capability:
                        self.assertIn(str(capability["intervalMinutes"]), text)

            if not any(c["kind"] == "groupEvents" for c in profile["capabilities"]):
                self.assertEqual(facts(card, "events"), [])

            if not any(c["kind"] == "heartbeat" for c in profile["capabilities"]):
                self.assertEqual(facts(card, "heartbeat"), [])

    def test_search_finds_a_card_by_capability_radio_role_and_battery_words(self):
        for profile in self.profiles:
            search = self.cards[profile["model"]]["attributes"]["data-search"]

            for capability in profile["capabilities"]:
                for word in build.CAPABILITY_LABELS[capability["kind"]].lower().split():
                    self.assertIn(word, search, profile["model"])

            if profile.get("batteryPowered"):
                self.assertIn("battery powered", search)

            if "radio" in profile:
                self.assertIn({"powerline": "powerline", "rf": "rf", "dual": "dual-band"}[profile["radio"]], search)

    def test_the_search_script_also_reads_the_text_of_the_card(self):
        self.assertIn("textContent", self.page)

    def test_the_page_stays_a_sane_size(self):
        self.assertLess(len(self.page.encode()), 400_000)


class CapabilityWordingTests(unittest.TestCase):
    def setUp(self):
        _, _, self.page, _ = catalog_page()
        self.text = page_text(self.page)

    def test_the_page_names_the_status_words_not_unverified(self):
        self.assertNotIn("unverified", self.text.lower())
        self.assertRegex(self.text, r"status \(inferred, conflicting or observed\)")
        self.assertIn("a value with no mark is documented", self.text.lower())

    def test_the_identities_column_says_what_documented_means(self):
        self.assertIn("An identity with no mark is counted as documented: it is read from the documents the profile cites, not confirmed on a device.", self.text)

    def test_generated_text_has_no_dash_and_no_temporal_words_even_in_cards(self):
        profile = {"model": "9", "name": "Plain", "capabilities": [{"kind": "dimmable"}, {"kind": "heartbeat", "group": "0x04", "intervalMinutes": 5}], "sources": ["S"], "radio": "rf", "batteryPowered": True,
                   "groups": [{"number": "0x04", "name": "Beat", "role": "controller"}], "engines": [{"category": "0x01", "subcategory": "0x01", "engine": "i2"}],
                   "commandSets": [{"commandSet": "a", "category": "0x01", "subcategory": "0x01"}],
                   "identities": [{"category": "0x01", "subcategory": "0x01"}]}
        bare = {"model": "8", "name": "Bare", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x02"}]}
        none = {"model": "7", "name": "None", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x03"}],
                "commandSets": [{"commandSet": "empty", "category": "0x01", "subcategory": "0x03"}]}
        sets = [{"id": "a", "name": "A", "operatingFlags": [{"name": "f", "label": "Flag one"}], "extendedSettings": {"values": [{"label": "Setting one"}]}, "standardCommands": [{}], "serialCommands": [{}]},
                {"id": "empty", "name": "E", "description": "Nothing.", "sources": ["S"]}]
        page = build.index_page([profile, bare, none], sets, "0.0.0")
        text = page_text(page)

        self.assertNotRegex(page, "[\u2013\u2014]")
        self.assertNotRegex(text.lower(), r"\b(now|currently|latest|recent|recently|soon|today|yet|still|new|newly|later|upcoming)\b")
        self.assertIn("Flag one", text)
        self.assertIn("The catalog has no command set for this device.", text)
        self.assertIn("deliberately holds no settings", text)


class LandingPageTests(unittest.TestCase):
    def test_summary_numbers_are_the_catalogs(self):
        profiles, command_sets, _, parser = catalog_page()
        coverage = build.coverage(profiles, command_sets)
        metrics = {key: int(value.strip()) for key, value in parser.metrics.items()}

        self.assertEqual(metrics["profiles"], coverage["profiles"])
        self.assertEqual(metrics["identities"], coverage["identities"])
        self.assertEqual(metrics["described"], coverage["described"])
        self.assertEqual(metrics["deliberatelyEmpty"], coverage["deliberatelyEmpty"])
        self.assertEqual(metrics["undescribed"], coverage["undescribed"])

        for status in build.STATUSES:
            self.assertEqual(metrics[f"commandSet-{status}"], coverage["commandSetStatuses"][status])
            self.assertEqual(metrics[f"identity-{status}"], coverage["identityStatuses"][status])

    def test_explains_each_status_in_one_sentence(self):
        _, _, page, _ = catalog_page()

        for status in build.STATUSES:
            self.assertIn(html.escape(build.STATUS_EXPLANATIONS[status]), page)
            self.assertEqual(build.STATUS_EXPLANATIONS[status].count("."), 1)

    def test_a_card_names_the_statuses_its_own_values_carry(self):
        profile = {"model": "9", "name": "N", "capabilities": [], "sources": ["S"], "identities": [
            {"category": "0x01", "subcategory": "0x01", "verification": {"status": "observed", "note": "n"}},
            {"category": "0x01", "subcategory": "0x02", "verification": {"status": "inferred", "note": "n"}},
        ]}
        plain = {"model": "8", "name": "M", "capabilities": [], "sources": ["S"], "identities": [{"category": "0x01", "subcategory": "0x03"}]}
        page = build.index_page([profile, plain], [], "0.0.0")
        cards = page.split('<article class="card"')[1:]

        self.assertIn('data-verification="observed inferred"', cards[1])
        self.assertIn('class="status status-observed"', cards[1])
        self.assertIn('class="status status-inferred"', cards[1])
        self.assertNotIn("status-conflicting", cards[1])
        self.assertIn('data-verification=""', cards[0])
        self.assertNotIn('class="status', cards[0])

    def test_page_has_landmarks_and_ordered_headings(self):
        _, _, _, parser = catalog_page()
        levels = [int(tag[1]) for tag, _ in parser.headings]

        self.assertLessEqual({"header", "main", "footer"}, parser.landmarks)
        self.assertEqual(levels[0], 1)
        self.assertEqual(levels.count(1), 1)
        self.assertTrue(all(after - before <= 1 for before, after in zip(levels, levels[1:])))
        self.assertIn("How this catalog is built and how to help", [text for _, text in parser.headings])

    def test_page_makes_no_external_requests(self):
        _, _, _, parser = catalog_page()

        self.assertEqual([source for source in parser.sources if "//" in source], [])

    def test_page_links_the_api_the_repository_and_the_issue_route(self):
        _, _, _, parser = catalog_page()
        base = "https://github.com/brandtdaniels/insteon-device-catalog"

        for link in (f"{base}/blob/main/API.md", base, f"{base}/issues", f"{base}/pulls"):
            self.assertIn(link, parser.hrefs)

    def test_page_text_has_no_dash_and_no_temporal_words(self):
        _, _, page, _ = catalog_page()
        # The cards quote catalog data; the rest of the page is the page's own wording.
        text = re.sub(r"<(script|style|article)\b.*?</\1>", "", page, flags=re.S)
        text = re.sub(r"<[^>]+>", " ", text)

        self.assertNotRegex(page, "[\u2013\u2014]")
        self.assertNotRegex(text.lower(), r"\b(now|currently|latest|recent|recently|soon|today|yet|still|new|newly|later|upcoming)\b")


def registry_with(*documents):
    return {"documents": list(documents)}


def document(title="Leak Sensor Developer Notes", kind="developerNotes", **optional):
    return {"title": title, "kind": kind, **optional}


class DocumentRegistryTests(unittest.TestCase):
    def test_a_registered_title_is_accepted(self):
        titles = {"Leak Sensor Developer Notes"}

        self.assertEqual(build.source_problems("2852.json", {"sources": ["Leak Sensor Developer Notes"]}, titles), [])

    def test_an_unregistered_title_names_the_file_and_the_string(self):
        found = build.source_problems("2852.json", {"sources": ["Leak Sensor Developer Notes (draft)"]}, {"Leak Sensor Developer Notes"})

        self.assertEqual(len(found), 1)
        self.assertIn("2852.json", found[0])
        self.assertIn("Leak Sensor Developer Notes (draft)", found[0])

    def test_a_title_matches_exactly(self):
        titles = {"Leak Sensor Developer Notes"}

        for near in ("leak sensor developer notes", "Leak Sensor Developer Notes ", "Leak Sensor  Developer Notes"):
            self.assertEqual(len(build.source_problems("2852.json", {"sources": [near]}, titles)), 1, near)

    def test_nested_sources_are_checked(self):
        data = {"commands": [{"name": "x", "sources": ["Missing Title"]}]}

        self.assertEqual(len(build.source_problems("set.json", data, set())), 1)

    def test_a_valid_registry_has_no_problems(self):
        registry = registry_with(
            document(),
            document("Insteon Developer's Guide (2009)", "developersGuide", edition="2009"),
            document("Hub 2242 Quick Start Guide", "quickStart", url="https://cache.insteon.com/documentation/2242-qsg.pdf"),
        )

        self.assertEqual(build.registry_problems(registry), [])

    def test_a_duplicate_title_fails(self):
        found = build.registry_problems(registry_with(document(), document(kind="other")))

        self.assertEqual(len(found), 1)
        self.assertIn("Leak Sensor Developer Notes", found[0])
        self.assertIn("more than once", found[0])

    def test_a_malformed_entry_fails(self):
        malformed = [
            {"documents": "not a list"},
            registry_with("a string"),
            registry_with({"kind": "other"}),
            registry_with({"title": "No Kind"}),
            registry_with(document(title="")),
            registry_with(document(kind="notAKind")),
            registry_with(document(edition="")),
            registry_with(document(url="http://cache.insteon.com/a.pdf")),
            registry_with(document(url="not a url")),
            registry_with(document(unknown="field")),
            {"documents": [], "extra": 1},
            ["not an object"],
        ]

        for registry in malformed:
            self.assertNotEqual(build.registry_problems(registry), [], registry)

    def test_a_dash_in_any_field_fails(self):
        for entry in (
            document(title="Leak Sensor \u2014 Developer Notes"),
            document(title="Leak Sensor \u2013 Developer Notes"),
            document(edition="2009 \u2013 2010"),
        ):
            self.assertNotEqual(build.registry_problems(registry_with(entry)), [], entry)

    def test_a_ruled_out_term_in_a_title_fails(self):
        self.assertNotEqual(build.registry_problems(registry_with(document(title="INSTEON Leak Sensor Developer Notes"))), [])

    def test_the_catalogs_registry_is_valid(self):
        registry = json.loads((build.ROOT / "documents" / "registry.json").read_text())

        self.assertEqual(build.registry_problems(registry), [])

    def test_every_source_in_the_catalog_is_registered(self):
        titles, errors = build.load_registry()
        profiles, profile_errors = build.load_profiles()
        command_sets, command_set_errors = build.load_command_sets(profiles)
        found = []

        for profile in profiles:
            found += build.source_problems(f"{profile['model']}.json", profile, titles)

        for command_set in command_sets:
            found += build.source_problems(f"{command_set['id']}.json", command_set, titles)

        self.assertEqual(errors + profile_errors + command_set_errors + found, [])

    def test_the_registry_is_not_published(self):
        import subprocess
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([sys.executable, "-I", str(build.ROOT / "scripts" / "build.py"), "--output", directory], check=True, capture_output=True)

            self.assertEqual([path for path in pathlib.Path(directory).rglob("*") if "registry" in path.name], [])
