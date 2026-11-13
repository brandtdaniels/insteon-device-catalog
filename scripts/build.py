"""Validates the device profiles and bundles them into the published catalog.

Usage: python3 scripts/build.py [--output DIR]

Every file in devices/ must match schema/device-profile.schema.json, and no two profiles may
claim the same category, subcategory and firmware. The output is deterministic: the same
profiles always produce the same bytes, so the manifest's hash changes only when the data
does.
"""

import argparse
import hashlib
import html
import json
import pathlib
import re
import string
import sys

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The catalog's version, MAJOR.MINOR from the VERSION file and PATCH from the publishing
# workflow: the number of commits since VERSION last changed.
MAJOR_MINOR = (ROOT / "VERSION").read_text().strip()

if not re.fullmatch(r"\d+\.\d+", MAJOR_MINOR):
    sys.exit(f"VERSION must be MAJOR.MINOR, not {MAJOR_MINOR!r}")

MAJOR = MAJOR_MINOR.split(".")[0]


def load_profiles():
    schema = json.loads((ROOT / "schema" / "device-profile.schema.json").read_text())
    validator = jsonschema.Draft202012Validator(schema)
    profiles = []
    errors = []

    for path in sorted((ROOT / "devices").glob("*.json")):
        profile = json.loads(path.read_text())
        problems = [f"{path.name}: {error.json_path}: {error.message}" for error in validator.iter_errors(profile)]

        # The checks below read fields the schema requires, so they wait until it passes.
        if problems:
            errors += problems
            continue

        if path.stem != profile.get("model"):
            problems.append(f"{path.name}: the file name must be the model, {profile.get('model')!r}")

        kinds = [capability["kind"] for capability in profile.get("capabilities", [])]

        if len(kinds) != len(set(kinds)):
            problems.append(f"{path.name}: a capability kind appears more than once")

        problems += [f"{path.name}: {problem}" for problem in scoped_entry_problems(profile, "engines", "engine")]
        problems += [f"{path.name}: {problem}" for problem in modem_link_data_problems(profile)]
        problems += [f"{path.name}: {problem}" for problem in from_hub_problems(profile)]
        problems += [f"{path.name}: {problem}" for problem in scoped_entry_problems(profile, "commandSets", "command set")]

        errors += problems
        profiles.append(profile)

    errors += overlapping_identities(profiles)

    return profiles, errors


def modem_link_data_problems(profile):
    """Reports a modem's record data that names a byte twice, or a byte that gives neither or
    both of a fixed value and an identity byte."""
    problems = []

    for capability in profile["capabilities"]:
        for side, entries in capability.get("linkData", {}).items():
            numbers = [entry["byte"] for entry in entries]

            if len(numbers) != len(set(numbers)):
                problems.append(f"the modem's {side} record data names a byte twice")

            for entry in entries:
                if ("value" in entry) == ("identity" in entry):
                    problems.append(f"the modem's {side} record data {entry['name']} needs a value or an identity, not both")

    return problems


def from_hub_problems(profile):
    """Reports a fromHub leg whose device group isn't one of the profile's groups, a controller leg
    whose device group doesn't respond, a responder leg whose groups differ or whose device group
    can't be a controller, a device-first start whose first leg doesn't have the device as
    controller, and keepAwake on a device without batteries or with a raw message that's malformed
    or isn't configuration and idempotent."""
    from_hub = profile.get("lifecycle", {}).get("fromHub")

    if from_hub is None:
        return []

    problems = []
    groups = {group["number"]: group for group in profile.get("groups", [])}

    for index, leg in enumerate(from_hub["legs"], 1):
        group = groups.get(leg["deviceGroup"])

        if group is None:
            problems.append(f"fromHub leg {index} names device group {leg['deviceGroup']}, which isn't one of the profile's groups")
        elif leg["modem"] == "responder" and group["role"] == "responder":
            problems.append(f"fromHub leg {index} has the device control group {leg['deviceGroup']}, which is only a responder")
        elif leg["modem"] == "controller" and group["role"] == "controller":
            problems.append(f"fromHub leg {index} has the modem control the device's group {leg['deviceGroup']}, the Enter Linking Mode cmd2, which is only a controller")

        if leg["modem"] == "responder" and leg["modemGroup"] != leg["deviceGroup"]:
            problems.append(f"fromHub leg {index}: the modem responds to the device's group, so its group must be {leg['deviceGroup']}")

    if from_hub["deviceFirst"] and from_hub["legs"][0]["modem"] != "responder":
        problems.append("fromHub starts with the device, so its first leg needs the modem as responder")

    keep_awake = from_hub.get("keepAwake")

    if keep_awake is not None:
        if not profile.get("batteryPowered"):
            problems.append("fromHub keeps the device awake, but it isn't battery-powered")

        for key in ("send", "release"):
            message = keep_awake.get(key)

            if message is None or "command1" not in message:
                continue

            positions = [byte["position"] for byte in message.get("data", [])]
            positions += [14] if message.get("integrity") == "checksum" else []

            if len(positions) != len(set(positions)):
                problems.append(f"fromHub keepAwake {key} fills a user data byte twice")

            if not message.get("extended") and positions:
                problems.append(f"fromHub keepAwake {key} has user data, so it must be extended")

            if message["effect"] != "configuration" or not message["idempotent"]:
                problems.append(f"fromHub keepAwake {key} must be configuration and idempotent")

    return problems


def from_hub_command_set_problems(profile, command_sets):
    """Reports fromHub names that aren't in every command set the profile uses: allGroupsWhen
    flags, and keepAwake commands and flags; keepAwake commands that aren't configuration and
    idempotent; raw keepAwake bytes where a command set entry sends the same Set Operating Flags
    command; and raw keepAwake bytes whose effect differs from a standard or extended entry with
    those bytes."""
    from_hub = profile.get("lifecycle", {}).get("fromHub")

    if from_hub is None:
        return []

    problems = []
    used = sorted({entry["commandSet"] for entry in profile.get("commandSets", []) if entry["commandSet"] in command_sets})

    def flag(name):
        return [command_sets[used_id] for used_id in used if not any(f["name"] == name and "on" in f and "off" in f for f in command_sets[used_id].get("operatingFlags", []))]

    for index, leg in enumerate(from_hub["legs"], 1):
        if "allGroupsWhen" in leg:
            name = leg["allGroupsWhen"]["flag"]

            if not used or not all(any(f["name"] == name for f in command_sets[used_id].get("operatingFlags", [])) for used_id in used):
                problems.append(f"fromHub leg {index} depends on {name!r}, which not every command set the profile uses has")

    for key in ("send", "release"):
        message = from_hub.get("keepAwake", {}).get(key)

        if message is None:
            continue

        if "command" in message:
            names = lambda cs: {c["name"] for k in ("flagCommands", "standardCommands", "extendedCommands") for c in cs.get(k, [])}

            if not used or not all(message["command"] in names(command_sets[used_id]) for used_id in used):
                problems.append(f"fromHub keepAwake {key} names {message['command']!r}, which not every command set the profile uses has")
                continue

            for used_id in used:
                named = next(c for k in ("flagCommands", "standardCommands", "extendedCommands") for c in command_sets[used_id].get(k, []) if c["name"] == message["command"])

                if named["effect"] != "configuration" or not named["idempotent"]:
                    problems.append(f"fromHub keepAwake {key} names {message['command']!r}, which isn't configuration and idempotent in {used_id}")
        elif "flag" in message:
            if not used or flag(message["flag"]):
                problems.append(f"fromHub keepAwake {key} names the flag {message['flag']!r}, which not every command set the profile uses sets both ways")
        elif message["command1"] == "0x20":
            for used_id in used:
                cs = command_sets[used_id]
                sent = {c["command2"] for c in cs.get("flagCommands", [])} | {f[k] for f in cs.get("operatingFlags", []) for k in ("on", "off") if k in f}

                if message["command2"] in sent:
                    problems.append(f"fromHub keepAwake {key} gives raw bytes for a Set Operating Flags command {used_id} names; name it instead")

                kind = "extendedCommands" if message.get("extended") else "standardCommands"

                for entry in cs.get(kind, []):
                    if entry["command1"] == "0x20" and entry.get("command2") == message["command2"] and (entry["effect"], entry["idempotent"]) != (message["effect"], message["idempotent"]):
                        problems.append(f"fromHub keepAwake {key} has the bytes of {used_id}'s {entry['name']}, so it needs the same effect and idempotent")

    return problems


def selected_firmware(selection):
    """The firmware versions a selection includes, or every version for none."""
    if selection is None:
        return set(range(0x100))

    if "only" in selection:
        return {int(version, 16) for version in selection["only"]}

    return set(range(0x100)) - {int(version, 16) for version in selection["except"]}


def scoped_entry_problems(profile, field, label):
    """Reports entries of a field such as engines for identities the product doesn't have, and
    firmware versions two entries cover under the same identity."""
    identities = {(identity["category"], identity["subcategory"]) for identity in profile.get("identities", [])}
    claimed = {}
    problems = []

    for entry in profile.get(field, []):
        key = (entry["category"], entry["subcategory"])

        if key not in identities:
            problems.append(f"the {label} entry for {key[0]}/{key[1]} names an identity the product doesn't report")
            continue

        versions = selected_firmware(entry.get("firmware"))

        if versions & claimed.get(key, set()):
            problems.append(f"two {label} entries cover the same firmware under {key[0]}/{key[1]}")

        claimed[key] = claimed.get(key, set()) | versions

    return problems


def load_command_sets(profiles):
    """Loads the command sets, and reports those that don't match the schema and profiles that
    name a command set that doesn't exist."""
    schema = json.loads((ROOT / "schema" / "command-set.schema.json").read_text())
    validator = jsonschema.Draft202012Validator(schema)
    command_sets = []
    errors = []

    for path in sorted((ROOT / "commandSets").glob("*.json")):
        command_set = json.loads(path.read_text())
        schema_errors = [f"{path.name}: {error.json_path}: {error.message}" for error in validator.iter_errors(command_set)]

        # The checks below read fields the schema requires, so they wait until it passes.
        if schema_errors:
            errors += schema_errors
            continue

        if path.stem != command_set.get("id"):
            errors.append(f"{path.name}: the file name must be the id, {command_set.get('id')!r}")

        errors += [f"{path.name}: {problem}" for problem in command_set_problems(command_set)]
        command_sets.append(command_set)

    ids = {command_set.get("id") for command_set in command_sets}
    group_types = {command_set["id"]: {group_type["name"]: group_type for group_type in command_set.get("groupTypes", [])} for command_set in command_sets}
    flag_names = {command_set["id"]: {flag["name"] for flag in command_set.get("operatingFlags", [])} for command_set in command_sets}

    for profile in profiles:
        for entry in profile.get("commandSets", []):
            if entry["commandSet"] not in ids:
                errors.append(f"{profile['model']}.json: it names the command set {entry['commandSet']!r}, which doesn't exist")

        errors += [f"{profile['model']}.json: {problem}" for problem in from_hub_command_set_problems(profile, {cs["id"]: cs for cs in command_sets})]
        entries = {entry["commandSet"] for entry in profile.get("commandSets", []) if entry["commandSet"] in ids}
        kinds = {capability["kind"] for capability in profile["capabilities"]}

        for group in profile.get("groups", []):
            label = f"{profile['model']}.json: group {group['number']}"

            if "type" in group:
                for entry in sorted(entries):
                    group_type = group_types[entry].get(group["type"])

                    if group_type is None:
                        errors.append(f"{label} names the group type {group['type']!r}, which {entry} doesn't have")
                    elif group_type.get("state", {}).get("bitPerGroup") and int(group["number"], 16) > 8:
                        errors.append(f"{label} reads one bit per group, but a reply has bits for groups 1 to 8 only")
                    elif group_type.get("actions") and group["role"] == "controller":
                        errors.append(f"{label} is only a controller, but its group type has actions")
                    elif group_type["kind"] == "dimmer" and "dimmable" not in kinds:
                        errors.append(f"{label} is a dimmer, but the profile isn't dimmable")
                    elif group_type["kind"] == "relay" and "onOff" not in kinds and "dimmable" not in kinds:
                        errors.append(f"{label} is a relay, but the profile doesn't switch a load")

            if "activeWhen" in group:
                for entry in sorted(entries):
                    if group["activeWhen"]["flag"] not in flag_names[entry]:
                        errors.append(f"{label} depends on {group['activeWhen']['flag']!r}, which {entry} has no flag for")

            if profile.get("role") in ("controller", "responder") and group["role"] not in (profile["role"],):
                errors.append(f"{label} is a {group['role']}, but the profile is only a {profile['role']}")

    return command_sets, errors


def command_set_problems(command_set):
    """Reports names used twice, flags sharing a bit or a command, values sharing a byte, writes
    sharing a selector, and writes that fill a byte twice."""
    problems = []
    flags = command_set.get("operatingFlags", [])
    flag_commands = command_set.get("flagCommands", [])
    settings = command_set.get("extendedSettings", {})
    values = settings.get("values", [])
    writes = settings.get("writes", [])

    for kind, items in [("flag", flags + command_set.get("readings", []) + flag_commands), ("value", values), ("write", writes)]:
        names = [item["name"] for item in items]

        if len(names) != len(set(names)):
            problems.append(f"a {kind} name appears more than once")

    bits = [(flag["query"], flag["bit"]) for flag in flags]

    if len(bits) != len(set(bits)):
        problems.append("two operating flags share a bit")

    commands = [flag[key] for flag in flags for key in ("on", "off") if key in flag] + [command["command2"] for command in flag_commands]

    if len(commands) != len(set(commands)):
        problems.append("two Set Operating Flags commands share a cmd2")

    if len({value["byte"] for value in values}) != len(values):
        problems.append("two values share a byte")

    if len({write["selector"] for write in writes}) != len(writes):
        problems.append("two writes share a selector")

    for write in writes:
        positions = [byte["position"] for byte in write["bytes"]]

        if len(positions) != len(set(positions)):
            problems.append(f"the {write['name']} write fills a byte twice")

    return problems + message_problems(command_set) + presentation_problems(command_set) + effect_problems(command_set)


def effect_problems(command_set):
    """Reports commands whose effect or idempotent contradicts what the protocol or the command
    set says about them: a command never sent that isn't destructive, a Set Operating Flags
    command or an extended Set that's readOnly, a readOnly command that isn't idempotent, a
    command a group type acts or reads its state with, or a flag or value is set with, that isn't
    actuation, readOnly or configuration, and entries one message can match with different
    effects or idempotent: Set Operating Flags entries with the same cmd2, and extended commands
    whose bytes overlap."""
    problems = []
    entries = {kind: command_set.get(kind, []) for kind in ("flagCommands", "standardCommands", "extendedCommands")}
    effects = {command["name"]: command["effect"] for commands in entries.values() for command in commands}

    for kind, commands in entries.items():
        for command in commands:
            label = f"the {command['name']} command"
            set_flags = kind == "flagCommands" or command["command1"] == "0x20"
            fixed = {byte["position"]: byte["value"] for byte in command.get("fixed", [])}
            given = {position for field in command.get("parameters", []) for position in ([field["byte"]] if "byte" in field else field.get("bytes", []))}
            extended = kind == "extendedCommands"
            selector = fixed.get(2, "0x00") != "0x00" or 2 in given
            extended_set = extended and command["command1"] == "0x2E" and command["command2"] == "0x00" and selector
            properties_write = extended and command["command1"] == "0x2E" and command["command2"] == "0x01" and fixed.get(1) == "0x02"
            database_write = extended and command["command1"] == "0x2F" and (fixed.get(2) == "0x02" or 2 in given)

            if command.get("guard") == "never" and command["effect"] != "destructive":
                problems.append(f"{label} is never sent, so its effect must be destructive")

            if command["effect"] == "readOnly" and set_flags:
                problems.append(f"{label} is Set Operating Flags, which is never readOnly")
            elif command["effect"] == "readOnly" and extended_set:
                problems.append(f"{label} is an extended Set, which is never readOnly")
            elif command["effect"] == "readOnly" and properties_write:
                problems.append(f"{label} writes properties (cmd1 0x2E, cmd2 0x01, D1 0x02), which is never readOnly")
            elif command["effect"] == "readOnly" and database_write:
                problems.append(f"{label} writes with cmd1 0x2F and D2 0x02, which is never readOnly")

            if command["effect"] == "readOnly" and not command["idempotent"]:
                problems.append(f"{label} is readOnly, so it must be idempotent")

    serial = command_set.get("serialCommands", [])

    for command in serial:
        label = f"the {command['name']} serial command"

        if command.get("guard") == "never" and command["effect"] != "destructive":
            problems.append(f"{label} is never sent, so its effect must be destructive")

        if command["effect"] == "readOnly" and not command["idempotent"]:
            problems.append(f"{label} is readOnly, so it must be idempotent")

    # Serial commands one frame can match: the same number and no fixed byte that differs.
    for index, command in enumerate(serial):
        for other in serial[index + 1:]:
            if (command["effect"], command["idempotent"]) == (other["effect"], other["idempotent"]) or not serial_overlap(command, other):
                continue

            if command["effect"] == "readOnly" and serial_covers(command, other):
                problems.append(f"the {command['name']} serial command is readOnly, but it matches every frame the {other['name']} serial command does")
            elif other["effect"] == "readOnly" and serial_covers(other, command):
                problems.append(f"the {other['name']} serial command is readOnly, but it matches every frame the {command['name']} serial command does")
            else:
                problems.append(f"the {command['name']} serial command and the {other['name']} serial command can match the same frame, so they need the same effect and idempotent")

    for group_type in command_set.get("groupTypes", []):
        label = f"the {group_type['name']} group type"
        state = group_type.get("state")

        for action in group_type.get("actions", []):
            if effects.get(action["command"], "actuation") != "actuation":
                problems.append(f"{label}'s {action['name']} action names {action['command']!r}, which isn't actuation")

        if state is not None and effects.get(state["command"], "readOnly") != "readOnly":
            problems.append(f"{label} reads its state with {state['command']!r}, which isn't readOnly")

    for flag in command_set.get("operatingFlags", []):
        for key in ("onCommand", "offCommand"):
            if effects.get(flag.get(key), "configuration") != "configuration":
                problems.append(f"the {flag['name']} flag's {key} names {flag[key]!r}, which isn't configuration")

    for value in command_set.get("extendedSettings", {}).get("values", []):
        if effects.get(value.get("write"), "configuration") != "configuration":
            problems.append(f"the {value['name']} value is written by {value['write']!r}, which isn't configuration")

    # Set Operating Flags messages, by the cmd2 each entry sends, or None for any: an operating
    # flag's on and off, which are configuration, and the flag, standard and extended commands
    # with cmd1 0x20. A flag command goes as a standard or an extended message, so it can match
    # entries of either kind.
    enumerations = {enumeration["name"]: enumeration for enumeration in command_set.get("enumerations", [])}
    senders = [(f"the {flag['name']} flag", {flag[key] for key in ("on", "off") if key in flag}, ("configuration", True)) for flag in command_set.get("operatingFlags", []) if "on" in flag or "off" in flag]
    senders += [(f"the {command['name']} command", {command["command2"]}, (command["effect"], command["idempotent"])) for command in entries["flagCommands"]]

    for command in entries["standardCommands"] + entries["extendedCommands"]:
        if command["command1"] != "0x20":
            continue

        if "parameter" in command:
            enumeration = enumerations.get(command["parameter"].get("enumeration"))
            sent = {value["value"] for value in enumeration["values"]} if enumeration else None
        else:
            sent = {command.get("command2", "0x00")}

        senders.append((f"the {command['name']} command", sent, (command["effect"], command["idempotent"])))

    for index, (label, sent, effect) in enumerate(senders):
        for other_label, other_sent, other_effect in senders[index + 1:]:
            shared = sent & other_sent if sent is not None and other_sent is not None else (sent or other_sent)

            if effect != other_effect and (shared is None or shared):
                where = "any cmd2" if shared is None else "cmd2 " + ", ".join(sorted(shared))
                problems.append(f"{label} and {other_label} both send Set Operating Flags with {where}, so they need the same effect and idempotent")

    # Extended commands one message can match: an unfixed user data byte that isn't a parameter,
    # a perButton D1 or integrity is 0x00, so commands overlap only where every byte can agree.
    extended = entries["extendedCommands"]

    for index, command in enumerate(extended):
        for other in extended[index + 1:]:
            if (command["effect"], command["idempotent"]) == (other["effect"], other["idempotent"]) or not extended_overlap(command, other):
                continue

            if command["effect"] == "readOnly" and extended_covers(command, other):
                problems.append(f"the {command['name']} command is readOnly, but it matches every message the {other['name']} command does")
            elif other["effect"] == "readOnly" and extended_covers(other, command):
                problems.append(f"the {other['name']} command is readOnly, but it matches every message the {command['name']} command does")
            else:
                problems.append(f"the {command['name']} command and the {other['name']} command can match the same extended message, so they need the same effect and idempotent")

    return problems


def extended_bytes(command):
    """What an extended command's user data bytes D1 through D14 can hold: a fixed value, None
    for any value (a parameter, a perButton D1 or integrity), and 0x00 for every other byte."""
    found = {position: "0x00" for position in range(1, 15)}

    for field in command.get("parameters", []):
        for position in [field["byte"]] if "byte" in field else field.get("bytes", []):
            found[position] = None

    if command.get("perButton"):
        found[1] = None

    for position in {"checksum": [14], "crc": [13, 14]}.get(command.get("integrity"), []):
        found[position] = None

    for byte in command.get("fixed", []):
        found[byte["position"]] = byte["value"]

    return found


def extended_overlap(command, other):
    """Whether one extended message can match both commands."""
    mine, theirs = extended_bytes(command), extended_bytes(other)

    return (command["command1"], command["command2"]) == (other["command1"], other["command2"]) and all(mine[p] is None or theirs[p] is None or mine[p] == theirs[p] for p in mine)


def extended_covers(command, other):
    """Whether every extended message that matches other also matches command."""
    mine, theirs = extended_bytes(command), extended_bytes(other)

    return (command["command1"], command["command2"]) == (other["command1"], other["command2"]) and all(mine[p] is None or mine[p] == theirs[p] for p in mine)


def serial_bytes(command):
    """What a serial command's payload bytes can hold: a fixed value, or None for any value (a
    parameter). A byte that is neither is missing from the result."""
    found = {}

    for field in command.get("parameters", []):
        for position in [field["byte"]] if "byte" in field else field.get("bytes", []):
            found[position] = None

    for byte in command.get("fixed", []):
        found[byte["position"]] = byte["value"]

    return found


def serial_overlap(command, other):
    """Whether one serial frame can match both commands."""
    mine, theirs = serial_bytes(command), serial_bytes(other)

    return command["number"] == other["number"] and all(mine[p] is None or theirs[p] is None or mine[p] == theirs[p] for p in mine.keys() & theirs.keys())


def serial_covers(command, other):
    """Whether every serial frame that matches other also matches command."""
    mine, theirs = serial_bytes(command), serial_bytes(other)

    return command["number"] == other["number"] and all(mine[p] is None or mine[p] == theirs.get(p) for p in mine)


def serial_command_problems(command, field_problems, positions, overlaps, unit):
    """Reports a serial command whose number carries a device message, whose values name no
    payload byte or fill one twice, whose payload has a byte nothing fills, or whose reply reads a
    byte twice."""
    owner = f"the {command['name']} serial command"
    found = []

    if command["number"] in ("0x61", "0x62"):
        found.append(f"{owner} has number {command['number']}, which carries a device message and so isn't an entry")

    parameters = command.get("parameters", [])

    for field in parameters:
        found += field_problems(field, owner, True)

    filled = positions(parameters) + [(byte["position"], 0xFF) for byte in command.get("fixed", [])]

    if overlaps(filled):
        found.append(f"{owner}: it fills a {unit} twice")

    for position in range(1, max(serial_bytes(command), default=0) + 1):
        if position not in serial_bytes(command):
            found.append(f"{owner}: {unit} {position} is neither fixed nor a parameter")

    if "reply" in command:
        for field in command["reply"]:
            found += field_problems(field, f"{owner}'s reply", True)

        if overlaps(positions(command["reply"])):
            found.append(f"{owner}'s reply reads a {unit} twice")

    return found


def serial_frame_problems(serial):
    """Reports serial commands that send the same number and fixed bytes, and commands with one
    number but different payload lengths, which no frame could tell apart."""
    found = []
    keys = [(command["number"], tuple(sorted((byte["position"], byte["value"]) for byte in command.get("fixed", [])))) for command in serial]

    if len(keys) != len(set(keys)):
        found.append("two serial commands send the same number and fixed bytes")

    for index, command in enumerate(serial):
        for other in serial[index + 1:]:
            if command["number"] == other["number"] and max(serial_bytes(command), default=0) != max(serial_bytes(other), default=0):
                found.append(f"the {command['name']} and {other['name']} serial commands share number {command['number']} but differ in payload length")

    return found


def presentation_problems(command_set):
    """Reports value tables and group types that are named twice or name what doesn't exist, and
    defaults outside a value's range or table."""
    problems = []
    tables = {table["name"]: table for table in command_set.get("valueTables", [])}
    group_types = command_set.get("groupTypes", [])
    commands = {command["name"] for key in ("standardCommands", "extendedCommands") for command in command_set.get(key, [])}
    standard = {command["name"] for command in command_set.get("standardCommands", [])}

    if len(tables) != len(command_set.get("valueTables", [])):
        problems.append("a value table name appears more than once")

    for table in tables.values():
        values = [entry["value"] for entry in table["values"]]

        if len(values) != len(set(values)):
            problems.append(f"the {table['name']} value table names a value twice")

    for value in command_set.get("extendedSettings", {}).get("values", []):
        table = value.get("table")

        if table is not None and table not in tables:
            problems.append(f"the {value['name']} value names the value table {table!r}, which doesn't exist")

        if "default" in value:
            default = int(value["default"], 16)
            bounds = value.get("range")

            if bounds and not int(bounds["from"], 16) <= default <= int(bounds["through"], 16):
                problems.append(f"the {value['name']} value's default is outside its range")

            if table in tables and value["default"] not in {entry["value"] for entry in tables[table]["values"]}:
                problems.append(f"the {value['name']} value's default isn't in its value table")

    if len({group_type["name"] for group_type in group_types}) != len(group_types):
        problems.append("a group type name appears more than once")

    replies = {command["name"]: command.get("reply") for command in command_set.get("standardCommands", [])}
    parameters = {command["name"]: "parameter" in command for key in ("standardCommands", "extendedCommands") for command in command_set.get(key, [])}

    for group_type in group_types:
        label = f"the {group_type['name']} group type"
        state = group_type.get("state")

        if state is not None:
            if state["command"] not in standard:
                problems.append(f"{label} reads its state with {state['command']!r}, which isn't a standard command")
            elif replies[state["command"]] is None:
                problems.append(f"{label} reads its state with {state['command']!r}, which has no reply")
            elif state.get("bitPerGroup") and replies[state["command"]].get("kind") != "flags":
                problems.append(f"{label} reads one bit per group from a reply that isn't flags")

        on_when = (state or {}).get("onWhen")

        if on_when is not None:
            if int(on_when["value"], 16) & ~int(on_when["mask"], 16):
                problems.append(f"{label}'s onWhen value has bits outside its mask")

            if state.get("bitPerGroup") or "ranges" in state:
                problems.append(f"{label}'s state has onWhen with bitPerGroup or ranges")

        if ("armModes" in group_type) != (group_type["kind"] in ("alarm", "arming")):
            problems.append(f"{label} has armModes only if it's an alarm or arming group")

        outputs = group_type.get("outputs")

        if outputs is not None:
            bits = outputs["bits"]

            if any(int(bit["mask"], 16) == 0 for bit in bits) or len({bit["mask"] for bit in bits}) != len(bits) or len({bit["name"] for bit in bits}) != len(bits):
                problems.append(f"{label}'s outputs must have distinct, nonzero masks and distinct names")

            if "activeWhen" in outputs and outputs["activeWhen"]["flag"] not in {flag["name"] for flag in command_set.get("operatingFlags", [])}:
                problems.append(f"{label}'s outputs depend on {outputs['activeWhen']['flag']!r}, which isn't an operating flag")

            if not any(parameters.get(action["command"]) and "value" not in action for action in group_type.get("actions", [])):
                problems.append(f"{label} has outputs, but no action takes a parameter to select them in")

        ranges = [(int(r["from"], 16), int(r["through"], 16)) for r in (state or {}).get("ranges", [])]

        if any(low > high for low, high in ranges) or any(a[1] >= b[0] for a, b in zip(sorted(ranges), sorted(ranges)[1:])):
            problems.append(f"{label}'s state ranges are reversed or overlap")

        for side, entries in group_type.get("linkData", {}).items():
            numbers = [entry["byte"] for entry in entries]

            if len(numbers) != len(set(numbers)):
                problems.append(f"{label}'s {side} record data names a byte twice")

            for entry in entries:
                if entry.get("table") is not None and entry["table"] not in tables:
                    problems.append(f"{label}'s {side} record data names the value table {entry['table']!r}, which doesn't exist")

                bounds = entry.get("range")
                what = f"{label}'s {side} record data {entry['name']}"

                if not any(key in entry for key in ("value", "range", "table")) and not entry.get("perGroup"):
                    problems.append(f"{what} gives no value, range, table or perGroup")

                if entry.get("perGroup") and any(key in entry for key in ("value", "range", "table", "unit")):
                    problems.append(f"{what} is perGroup but also gives a value, range, table or unit")

                if "table" in entry and "unit" in entry:
                    problems.append(f"{what} has both a table and a unit")

                if "scale" in entry and "unit" not in entry:
                    problems.append(f"{what} has a scale but no unit")

                if bounds and int(bounds["from"], 16) > int(bounds["through"], 16):
                    problems.append(f"{what}'s range is reversed")

                if "value" in entry and bounds and not int(bounds["from"], 16) <= int(entry["value"], 16) <= int(bounds["through"], 16):
                    problems.append(f"{what} is outside its range")

                table = tables.get(entry.get("table"))

                if table is not None:
                    values = [int(v["value"], 16) for v in table["values"]]

                    if "value" in entry and int(entry["value"], 16) not in values:
                        problems.append(f"{what}'s value isn't in its table")

                    if bounds and any(not int(bounds["from"], 16) <= v <= int(bounds["through"], 16) for v in values):
                        problems.append(f"{what}'s table has values outside its range")

        names = [action["name"] for action in group_type.get("actions", [])]

        if len(names) != len(set(names)):
            problems.append(f"{label} names an action twice")

        holding = group_type.get("stateHolding")

        if holding is not None:
            if group_type["kind"] != "relay":
                problems.append(f"{label} has stateHolding, which only a relay group type has")

            if holding["restState"] not in names:
                problems.append(f"{label}'s stateHolding rests in {holding['restState']!r}, which isn't one of its actions")

            if not holding["releasedBy"] and "pulsesOnEveryCommandWhen" in holding:
                problems.append(f"{label}'s stateHolding has pulsesOnEveryCommandWhen, but no releasedBy flag releases the relay")

            flag_names = {flag["name"] for flag in command_set.get("operatingFlags", [])}

            for name in holding["releasedBy"] + [name for flag_set in holding.get("pulsesOnEveryCommandWhen", []) for name in flag_set]:
                if name not in flag_names:
                    problems.append(f"{label}'s stateHolding names {name!r}, which isn't an operating flag")

        for action in group_type.get("actions", []):
            if action["command"] not in commands:
                problems.append(f"{label}'s {action['name']} action names the command {action['command']!r}, which doesn't exist")
            elif "value" in action and not parameters[action["command"]]:
                problems.append(f"{label}'s {action['name']} action gives a value to {action['command']!r}, which takes none")

    extended = {command["name"] for command in command_set.get("extendedCommands", [])}
    flag_names = {flag["name"] for flag in command_set.get("operatingFlags", [])}
    # Extended message fields that hold the operating flags byte: a flags field with a bit named
    # for one of the command set's operating flags.
    flags_bytes = {
        field["name"]
        for command in command_set.get("extendedCommands", [])
        for field in command.get("parameters", []) + command.get("reply", {}).get("values", [])
        if any(bit["name"] in flag_names for bit in field.get("bits", []))
    }

    for value in command_set.get("extendedSettings", {}).get("values", []):
        label = f"the {value['name']} value"

        if (value["name"] == "operatingFlags" or value["name"] in flags_bytes) and "flagsQuery" not in value:
            problems.append(f"{label} holds the operating flags byte, so it needs flagsQuery")

        if value.get("kind") == "buttons" and ("unit" in value or "table" in value):
            problems.append(f"{label} is buttons but has a unit or table")

        if "table" in value and "unit" in value:
            problems.append(f"{label} has both a table and a unit")

        if "scale" in value and "unit" not in value:
            problems.append(f"{label} has a scale but no unit")

        if value.get("write") is not None and value["write"] not in extended:
            problems.append(f"{label} is written by {value['write']!r}, which isn't an extended command")

        if "flagsQuery" in value:
            if value["flagsQuery"] not in {flag["query"] for flag in command_set.get("operatingFlags", [])}:
                problems.append(f"{label} is the operating flags byte for query {value['flagsQuery']}, which no operating flag reads")

            if any(key in value for key in ("kind", "range", "table", "unit", "scale")):
                problems.append(f"{label} is an operating flags byte, so it can't have a kind, range, table, unit or scale")

        if value.get("table") in tables and value.get("range"):
            bounds = value["range"]

            for entry in tables[value["table"]]["values"]:
                if not int(bounds["from"], 16) <= int(entry["value"], 16) <= int(bounds["through"], 16):
                    problems.append(f"{label}'s table has a value outside its range")
                    break

    for flag in command_set.get("operatingFlags", []):
        if flag["name"] in GUARDED_FLAGS and flag.get("guard") != GUARDED_FLAGS[flag["name"]]:
            problems.append(f"the {flag['name']} flag needs guard {GUARDED_FLAGS[flag['name']]!r}")

        undocumented = KEPT_WITHOUT_DOCUMENTED_DEFAULT.get(command_set["id"], set())

        if GUARDED_FLAGS.get(flag["name"]) == "keep" and flag["name"] not in KEPT_MODES | undocumented and "default" not in flag:
            problems.append(f"the {flag['name']} flag is kept, so it needs a default")

    # Set Operating Flags commands, found by the bytes they send: every flag command, and any
    # standard or extended command with cmd1 0x20. One that turns a guarded flag on, by its name or
    # by a cmd2 that the command set's own flags or named on-commands use for that, is never sent.
    set_flags = [command for command in command_set.get("flagCommands", [])]
    set_flags += [command for key in ("standardCommands", "extendedCommands") for command in command_set.get(key, []) if command["command1"] == "0x20" and "command2" in command]
    dangerous = {flag["on"] for flag in command_set.get("operatingFlags", []) if flag["name"] in GUARDED_FLAGS and flag["name"] not in KEPT_MODES and "on" in flag}
    dangerous |= {command["command2"] for command in set_flags if command["name"] in NEVER_SENT}

    for command in set_flags:
        if (command["name"] in NEVER_SENT or command["command2"] in dangerous) and command.get("guard") != "never":
            problems.append(f"the {command['name']} command turns a guarded flag on, so it needs guard 'never'")

    for key in ("standardCommands", "extendedCommands"):
        for command in command_set.get(key, []):
            if command["name"] in NEVER_SENT and command["command1"] != "0x20" and command.get("guard") != "never":
                problems.append(f"the {command['name']} command needs guard 'never'")

    for command in command_set.get("extendedCommands", []):
        for field in command.get("parameters", []):
            for bit in field.get("bits", []):
                if bit["name"] in GUARDED_FLAGS and bit.get("guard") != GUARDED_FLAGS[bit["name"]]:
                    problems.append(f"the {command['name']} command's {bit['name']} bit needs guard {GUARDED_FLAGS[bit['name']]!r}")

    flags = {flag["name"]: flag for flag in command_set.get("operatingFlags", [])}
    changed = [entry["flag"] for entry in command_set.get("linkingChanges", [])]

    if len(changed) != len(set(changed)):
        problems.append("linkingChanges names a flag twice")

    for name in changed:
        flag = flags.get(name)

        if flag is None:
            problems.append(f"linkingChanges names {name!r}, which isn't an operating flag")
        elif "guard" in flag:
            problems.append(f"linkingChanges names {name!r}, which has a guard, so no linking flow may change it")
        elif "on" not in flag or "off" not in flag:
            problems.append(f"linkingChanges names {name!r}, which Set Operating Flags can't set both ways")

    for flag in command_set.get("operatingFlags", []):
        for key in ("onCommand", "offCommand"):
            if key in flag and flag[key] not in standard:
                problems.append(f"the {flag['name']} flag's {key} names {flag[key]!r}, which isn't a standard command")

    return problems


def message_problems(command_set):
    """Reports message names used twice, standard commands and direct messages that share a
    command, values in the wrong place or with an encoding that doesn't fit their kind, user data
    bytes filled twice, and names of flags and enumerations that don't exist."""
    problems = []
    standard = command_set.get("standardCommands", [])
    extended = command_set.get("extendedCommands", [])
    direct = command_set.get("directMessages", [])
    serial = command_set.get("serialCommands", [])
    enumerations = {enumeration["name"]: enumeration for enumeration in command_set.get("enumerations", [])}
    flag_names = {flag["name"] for flag in command_set.get("operatingFlags", [])}

    names = [item["name"] for item in standard + extended + direct + serial]

    if len(names) != len(set(names)):
        problems.append("a command or message name appears more than once")

    if len(enumerations) != len(command_set.get("enumerations", [])):
        problems.append("an enumeration name appears more than once")

    for enumeration in enumerations.values():
        if len({value["value"] for value in enumeration["values"]}) != len(enumeration["values"]):
            problems.append(f"the {enumeration['name']} enumeration names a value twice")

        if len({value["name"] for value in enumeration["values"]}) != len(enumeration["values"]):
            problems.append(f"the {enumeration['name']} enumeration uses a name twice")

    def command2s(command):
        """The cmd2 values a standard command sends, or None for any."""
        if "parameter" not in command:
            return {command.get("command2", "0x00")}

        enumeration = enumerations.get(command["parameter"].get("enumeration"))

        return {value["value"] for value in enumeration["values"]} if enumeration else None

    for index, command in enumerate(standard):
        for other in standard[index + 1:]:
            if command["command1"] != other["command1"]:
                continue

            mine, theirs = command2s(command), command2s(other)

            if mine is None or theirs is None or mine & theirs:
                problems.append(f"the {command['name']} and {other['name']} commands share a cmd1 and cmd2")

    def extended_key(command1, command2, fixed_bytes):
        return (command1, command2, tuple(sorted((byte["position"], byte["value"]) for byte in fixed_bytes)))

    requests = [extended_key(command["command1"], command["command2"], command.get("fixed", [])) for command in extended]
    replies = [extended_key(command["reply"].get("command1", command["command1"]), command["reply"]["command2"], command["reply"].get("match", [])) for command in extended if "reply" in command]

    if len(requests) != len(set(requests)):
        problems.append("two extended commands send the same cmd1, cmd2 and fixed bytes")

    if len(replies) != len(set(replies)):
        problems.append("two extended replies can't be told apart by their cmd1, cmd2 and match bytes")

    for item in command_set.get("operatingFlags", []) + command_set.get("flagCommands", []):
        if "extendedWhen" in item and item["extendedWhen"] not in flag_names:
            problems.append(f"the {item['name']} flag names the operating flag {item['extendedWhen']!r}, which doesn't exist")

    if len({message["command1"] for message in direct}) != len(direct):
        problems.append("two direct messages share a cmd1")

    def field_problems(field, owner, extended_message):
        found = []
        located = ("byte" in field) + ("bytes" in field)

        if extended_message and located != 1:
            found.append(f"{owner}: the {field['name']} value needs a byte or bytes")

        if not extended_message and located:
            found.append(f"{owner}: the {field['name']} value is in cmd2, so it can't name user data bytes")

        kind = field.get("kind", "number")

        if (kind == "enumeration") != ("enumeration" in field):
            found.append(f"{owner}: the {field['name']} value names an enumeration only if its kind is enumeration")
        elif "enumeration" in field and field["enumeration"] not in enumerations:
            found.append(f"{owner}: the {field['name']} value names the enumeration {field['enumeration']!r}, which doesn't exist")

        if (kind == "flags") != ("bits" in field):
            found.append(f"{owner}: the {field['name']} value names bits only if its kind is flags")

        if "mask" in field and (int(field["mask"], 16) == 0 or "bytes" in field):
            found.append(f"{owner}: the {field['name']} value's mask must pick out some bits of a single byte")

        if kind != "number" and any(key in field for key in ("scale", "unit", "signed")):
            found.append(f"{owner}: the {field['name']} value has a scale, unit or sign, which only a number can have")

        if "range" in field and field["range"]["from"] > field["range"]["through"]:
            found.append(f"{owner}: the {field['name']} value's range runs backward")

        bits = field.get("bits", [])

        if any(int(bit["mask"], 16) == 0 for bit in bits) or len({bit["mask"] for bit in bits}) != len(bits) or len({bit["name"] for bit in bits}) != len(bits):
            found.append(f"{owner}: the {field['name']} value's bits must have distinct, nonzero masks and distinct names")

        if kind == "buttons" and not extended_message:
            found.append(f"{owner}: the {field['name']} value can't be buttons in cmd2")

        return found

    def reserved(integrity):
        return [(position, 0xFF) for position in {"checksum": [14], "crc": [13, 14]}.get(integrity, [])]

    def positions(fields):
        """The user data bytes the values fill, each with the bits it fills."""
        found = []

        for field in fields:
            for position in [field["byte"]] if "byte" in field else field.get("bytes", []):
                found.append((position, int(field.get("mask", "0xFF"), 16)))

        return found

    def overlaps(filled):
        return any(a[0] == b[0] and a[1] & b[1] for index, a in enumerate(filled) for b in filled[index + 1:])

    for command in standard:
        owner = f"the {command['name']} command"

        for key in ("parameter", "reply", "followUp"):
            if key in command:
                problems += field_problems(command[key], owner, False)

        if "extendedWhen" in command and command["extendedWhen"] not in flag_names:
            problems.append(f"{owner}: it names the operating flag {command['extendedWhen']!r}, which doesn't exist")

    for command in extended:
        owner = f"the {command['name']} command"
        parameters = command.get("parameters", [])

        for field in parameters:
            problems += field_problems(field, owner, True)

        filled = positions(parameters) + [(byte["position"], 0xFF) for byte in command.get("fixed", [])] + reserved(command.get("integrity")) + ([(1, 0xFF)] if command.get("perButton") else [])

        if overlaps(filled):
            problems.append(f"{owner}: it fills a user data byte twice")

        if "reply" in command:
            reply = command["reply"]

            for field in reply["values"]:
                problems += field_problems(field, f"{owner}'s reply", True)

            read = positions(reply["values"]) + [(byte["position"], 0xFF) for byte in reply.get("match", [])] + reserved(reply.get("integrity"))

            if overlaps(read):
                problems.append(f"{owner}'s reply reads a user data byte twice")

    for command in serial:
        problems += serial_command_problems(command, field_problems, positions, overlaps, "payload byte")

    problems += serial_frame_problems(serial)

    for message in direct:
        problems += field_problems(message["value"], f"the {message['name']} message", False)

    if "displayScale" in command_set:
        known = flag_names | {field["name"] for command in extended for field in command.get("reply", {}).get("values", [])}
        known |= {bit["name"] for command in extended for field in command.get("reply", {}).get("values", []) for bit in field.get("bits", [])}
        known |= {value["name"] for value in command_set.get("extendedSettings", {}).get("values", [])}

        if command_set["displayScale"]["celsiusWhen"] not in known:
            problems.append(f"the displayScale names {command_set['displayScale']['celsiusWhen']!r}, which isn't a flag, value or bit")

    return problems


def firmware_range(identity):
    firmware = identity.get("firmware")

    if firmware is None:
        return 0x00, 0xFF

    return int(firmware["from"], 16), int(firmware["through"], 16)


def overlapping_identities(profiles):
    """Reports identities that two profiles, or one profile twice, claim for the same firmware."""
    claimed = {}
    errors = []

    for profile in profiles:
        for identity in profile["identities"]:
            key = (identity["category"], identity["subcategory"])
            low, high = firmware_range(identity)

            for other_model, other_low, other_high in claimed.get(key, []):
                if low <= other_high and other_low <= high:
                    errors.append(f"{profile['model']} and {other_model} both claim {key[0]}/{key[1]} for overlapping firmware")

            claimed.setdefault(key, []).append((profile["model"], low, high))

    return errors


# Operating flags that can cut a device off, lock it or change the message form it accepts, and
# the guard each needs wherever an app can write it: as a flag, or as a bit of a flags parameter.
GUARDED_FLAGS = {
    "programmingLock": "neverSet",
    "radioOff": "keep",
    "powerLineOff": "keep",
    "powerlineOff": "keep",
    "checksumRequired": "keep",
    "checksumRequiredOn": "keep",
    "extendedCommandsOnly": "keep",
}

# Kept flags that are a supported mode rather than a fault: no Set Operating Flags command that
# sets one is dangerous, and the flag needs no default.
KEPT_MODES = {"extendedCommandsOnly"}

# Kept flags whose command set's sources give no factory state, so they carry no default. Every
# other kept flag needs one, so software can report a device whose flag differs from it.
KEPT_WITHOUT_DOCUMENTED_DEFAULT = {
    "fanLinc": {"checksumRequired"},
    "inLineLinc": {"radioOff", "powerLineOff", "checksumRequired"},
    "inLineLincRelay": {"checksumRequired"},
    "keypadLinc": {"checksumRequired"},
    "ledBulb": {"radioOff", "powerLineOff", "checksumRequired"},
    "outletLinc": {"checksumRequired"},
    "switchLincDimmer": {"radioOff", "powerLineOff", "checksumRequired"},
    "switchLincRelay": {"radioOff", "powerLineOff", "checksumRequired"},
}

# Set Operating Flags commands that turn one of those on, which an app never sends.
NEVER_SENT = {"programmingLockOn", "radioOff", "powerLineOff", "powerlineOff", "checksumOn", "checksumRequiredOn"}


# Forms CONVENTIONS.md rules out of the catalog's prose, and what to write instead.
RULED_OUT_TERMS = [
    (r"\bINSTEON\b", "Insteon"),
    (r"(?<![.\w])[iI]2cs\b|\bI2CS\b", "i2CS"),
    (r"\b[Aa]cknowledgement", "acknowledgment"),
    (r"\b[Pp]ower line", "powerline"),
    (r"\bon level\b", "on-level"),
    (r"\b(2242|2245) Hub\b", "Hub 2242, Hub 2245"),
    (r"\bAll-Link|\ball-link", "ALL-Link"),
    (r"(?<!ALL-)\b[Ll]ink database", "ALL-Link database"),
    (r"\bclean-up", "cleanup"),
    (r"\b[Ss]et button\b", "SET button"),
    (r"(?<!Insteon )(?<!Modem )(?<!Hub )\b[Dd]eveloper'?s? [Gg]uides?\b|\b[Tt]he guide\b", "the document's title, such as Leak Sensor Developer Notes or Insteon Developer's Guide"),
]


def term_problems(label, value, key=None):
    """The ruled-out terms in a profile's or command set's descriptions, notes and names."""

    problems = []

    if isinstance(value, dict):
        for child_key, child in value.items():
            problems += term_problems(label, child, child_key)
    elif isinstance(value, list):
        for child in value:
            problems += term_problems(label, child, key)
    elif isinstance(value, str) and (key in {"description", "note", "notes", "sources", "label", "section", "text", "expect"} or (key == "name" and " " in value)):
        prose = re.sub(r"`[^`]*`", "", value)

        for pattern, replacement in RULED_OUT_TERMS:
            if found := re.search(pattern, prose):
                problems.append(f"{label}: {found.group(0)!r} in {key}; use {replacement}")

    return problems

REGISTRY_PATH = ROOT / "documents" / "registry.json"
# What kind of document a registry entry is.
DOCUMENT_KINDS = {
    "commandTables",
    "developerDocumentation",
    "developerNotes",
    "developersGuide",
    "deviceCategories",
    "deviceDefinitions",
    "ownersManual",
    "productCatalog",
    "productGuide",
    "quickStart",
    "supportArticle",
    "other",
}
DOCUMENT_FIELDS = {"title", "kind", "edition", "url"}


def document_problems(position, entry):
    """What is wrong with one registry entry."""

    if not isinstance(entry, dict):
        return [f"{REGISTRY_PATH.name}: entry {position} must be an object"]

    problems = []
    title = entry.get("title")
    label = f"{REGISTRY_PATH.name}: entry {position}" + (f" ({title!r})" if isinstance(title, str) else "")

    for field in sorted(set(entry) - DOCUMENT_FIELDS):
        problems.append(f"{label}: unknown field {field!r}")

    for field in ("title", "kind"):
        if not isinstance(entry.get(field), str) or not entry[field].strip():
            problems.append(f"{label}: {field} must be a non-empty string")

    if entry.get("kind") not in DOCUMENT_KINDS and isinstance(entry.get("kind"), str):
        problems.append(f"{label}: kind {entry['kind']!r} is not one of {sorted(DOCUMENT_KINDS)}")

    if "edition" in entry and (not isinstance(entry["edition"], str) or not entry["edition"].strip()):
        problems.append(f"{label}: edition must be a non-empty string")

    if "url" in entry and (not isinstance(entry["url"], str) or not re.fullmatch(r"https://[^\s/]+(/\S*)?", entry["url"])):
        problems.append(f"{label}: url must be an https URL")

    for field, value in entry.items():
        if isinstance(value, str) and re.search("[\u2013\u2014]", value):
            problems.append(f"{label}: {field} has a dash; rewrite it with a comma, colon or hyphen")

    if isinstance(title, str):
        problems += term_problems(label, title, "sources")

    return problems


def dash_problems(root=ROOT):
    """The files under devices, commandSets and documents that hold an em or en dash."""

    problems = []

    for directory in ("devices", "commandSets", "documents"):
        for path in sorted((root / directory).glob("*.json")):
            if re.search("[\u2013\u2014]", path.read_text()):
                problems.append(f"{directory}/{path.name}: has an em or en dash; use a hyphen, comma or colon")

    return problems


def registry_problems(registry):
    """What is wrong with the document registry: its shape, each entry, and repeated titles."""

    if not isinstance(registry, dict) or set(registry) != {"documents"} or not isinstance(registry["documents"], list):
        return [f'{REGISTRY_PATH.name}: must be an object with only a "documents" list']

    problems = []
    seen = set()

    for position, entry in enumerate(registry["documents"]):
        problems += document_problems(position, entry)
        title = entry.get("title") if isinstance(entry, dict) else None

        if isinstance(title, str) and title in seen:
            problems.append(f"{REGISTRY_PATH.name}: title {title!r} appears more than once")

        if isinstance(title, str):
            seen.add(title)

    return problems


def load_registry():
    """The registered titles, and what is wrong with the registry file."""

    try:
        registry = json.loads(REGISTRY_PATH.read_text())
    except (OSError, ValueError) as error:
        return set(), [f"{REGISTRY_PATH.name}: {error}"]

    problems = registry_problems(registry)

    if problems:
        return set(), problems

    return {entry["title"] for entry in registry["documents"]}, []


def source_problems(label, value, titles, key=None):
    """The strings in any sources list of a profile or command set that are not registered titles."""

    problems = []

    if isinstance(value, dict):
        for child_key, child in value.items():
            problems += source_problems(label, child, titles, child_key)
    elif isinstance(value, list):
        for child in value:
            problems += source_problems(label, child, titles, key)
    elif key == "sources" and isinstance(value, str) and value not in titles:
        problems.append(f"{label}: source {value!r} is not in {REGISTRY_PATH.relative_to(ROOT)}; register the document or cite its exact title")

    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output", type=pathlib.Path, help="where to write the catalog, its manifest and schemas, under v<MAJOR>/")
    parser.add_argument("--patch", type=int, default=0, help="the version's PATCH number, from the publishing workflow")
    parser.add_argument("--built", help="when the catalog was built, as an ISO 8601 date and time, from the publishing workflow")
    arguments = parser.parse_args()

    profiles, errors = load_profiles()
    command_sets, command_set_errors = load_command_sets(profiles)
    errors += command_set_errors
    titles, registry_errors = load_registry()
    errors += registry_errors
    errors += dash_problems()

    for profile in profiles:
        errors += term_problems(f"{profile['model']}.json", profile)

        if not registry_errors:
            errors += source_problems(f"{profile['model']}.json", profile, titles)

    for command_set in command_sets:
        errors += term_problems(f"{command_set['id']}.json", command_set)

        if not registry_errors:
            errors += source_problems(f"{command_set['id']}.json", command_set, titles)

    for error in errors:
        print(error, file=sys.stderr)

    if errors:
        sys.exit(1)

    print(f"{len(profiles)} profiles and {len(command_sets)} command sets are valid")

    if arguments.output is None:
        return

    version = f"{MAJOR_MINOR}.{arguments.patch}"
    # The version stays out of the catalog itself, so its bytes, and its SHA-256, change only
    # when its data does.
    catalog = json.dumps({"devices": profiles, "commandSets": command_sets}, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    manifest = {
        "version": version,
        "devices": len(profiles),
        "catalog": "catalog.json",
        "sha256": hashlib.sha256(catalog.encode()).hexdigest(),
    }

    if arguments.built:
        manifest["built"] = arguments.built

    directory = arguments.output / f"v{MAJOR}"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "catalog.json").write_text(catalog)
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    (directory / "device-profile.schema.json").write_text((ROOT / "schema" / "device-profile.schema.json").read_text())
    (directory / "command-set.schema.json").write_text((ROOT / "schema" / "command-set.schema.json").read_text())
    (arguments.output / "index.html").write_text(index_page(profiles, command_sets, version))


# The category names the Insteon Developer's Guide gives.
CATEGORY_NAMES = {
    "0x00": "Generalized Controllers",
    "0x01": "Dimmable Lighting Control",
    "0x02": "Switched Lighting Control",
    "0x03": "Network Bridges",
    "0x04": "Irrigation Control",
    "0x05": "Climate Control",
    "0x06": "Pool and Spa Control",
    "0x07": "Sensors and Actuators",
    "0x08": "Home Entertainment",
    "0x09": "Energy Management",
    "0x0A": "Built-In Appliance Control",
    "0x0B": "Plumbing",
    "0x0C": "Communication",
    "0x0D": "Computer Control",
    "0x0E": "Window Coverings",
    "0x0F": "Access Control",
    "0x10": "Security, Health, Safety",
    "0x11": "Surveillance",
    "0x12": "Automotive",
    "0x13": "Pet Care",
    "0x14": "Toys",
    "0x15": "Timekeeping",
    "0x16": "Holiday",
}


# What each category holds, for the page's sections.
CATEGORY_DESCRIPTIONS = {
    "0x00": "Controllers that send commands rather than switch a load of their own, such as remotes, tabletop controllers and range extenders.",
    "0x01": "Dimmers: wall switches, keypads, plug-in and in-line modules, outlets and bulbs that dim the light they control.",
    "0x02": "On/off switches: wall switches, keypads, plug-in and in-line modules, outlets and load controllers that switch what they control.",
    "0x03": "Network bridges that connect a computer, app or network to Insteon, such as modems, Hubs and USB adapters.",
    "0x04": "Irrigation controllers, such as sprinkler valve controllers.",
    "0x05": "Climate control: thermostats and thermostat adapters.",
    "0x06": "Pool and spa controls, such as pump and heater controllers.",
    "0x07": "Sensors and actuators: modules with inputs that sense contact closures and voltages, and relays that drive other equipment.",
    "0x08": "Home entertainment controls, such as audio and video equipment.",
    "0x09": "Energy management: power meters and high-current load controllers.",
    "0x0E": "Window coverings: modules and motors for drapes, shades and shutters.",
    "0x0F": "Access control: locks, deadbolts and garage door controls.",
    "0x10": "Security, health and safety: open/close, motion and leak sensors, and smoke alarm bridges.",
}

# How the page names each capability kind.
CAPABILITY_LABELS = {
    "onOff": "On/off",
    "dimmable": "Dimmable",
    "modem": "Modem",
    "hub": "Hub",
    "hubPro": "Hub Pro",
    "thermostat": "Thermostat",
    "groupEvents": "Group events",
    "heartbeat": "Heartbeat",
}

# How the page names each engine.
ENGINE_LABELS = {"i1": "i1", "i2": "i2", "i2cs": "i2CS"}


def engine_note(entry):
    """How the page shows an identity's engine, with the firmware versions in its tooltip."""
    label = ENGINE_LABELS[entry["engine"]]
    selection = entry.get("firmware")

    if selection is None:
        return label, f"Every firmware version runs {label}."

    if "only" in selection:
        return f"{label} on some firmware", f"Firmware {', '.join(selection['only'])} runs {label}."

    return f"{label} on most firmware", f"Every firmware version except {', '.join(selection['except'])} runs {label}."


def capability_descriptions():
    """Each capability kind's description, from the schema."""
    schema = json.loads((ROOT / "schema" / "device-profile.schema.json").read_text())

    return {option["properties"]["kind"]["const"]: option["description"] for option in schema["$defs"]["capability"]["oneOf"]}


# The verification statuses, in the order the page lists them.
STATUSES = ("observed", "documented", "inferred", "conflicting")

# One sentence each, for the page. They say what the README says a status means.
STATUS_EXPLANATIONS = {
    "observed": "Seen on a real device, with the firmware it was running recorded.",
    "documented": "An Insteon document gives it and none of the catalog's sources disagree.",
    "inferred": "No document states it, so it is read from an example, a similar product or how the product behaves.",
    "conflicting": "Insteon's documents disagree, and the note says which value the catalog uses.",
}

# The keys of a command set that describe it rather than the product's behavior.
COMMAND_SET_DESCRIPTIVE_KEYS = {"id", "name", "description", "notes", "sources"}


def marked_statuses(value):
    """The status of every `verification` in value, nested at any depth."""
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


def status_counts(statuses):
    """How many of each status are in statuses, in the page's order."""
    return {status: statuses.count(status) for status in STATUSES}


def coverage(profiles, command_sets):
    """What the catalog covers, counted from its data.

    A value with no `verification` is documented, so an identity without one counts as
    documented. A command set's values are counted only where they carry a mark. A profile has a
    command set when one of its entries names a command set that describes behavior, and
    deliberately has none when every entry names a command set that says there is nothing to read
    or write.
    """
    describes_behavior = {command_set["id"]: bool(set(command_set) - COMMAND_SET_DESCRIPTIVE_KEYS) for command_set in command_sets}
    described = deliberately_empty = 0

    for profile in profiles:
        entries = [describes_behavior[entry["commandSet"]] for entry in profile.get("commandSets", [])]
        described += any(entries)
        deliberately_empty += bool(entries) and not any(entries)

    identities = [identity for profile in profiles for identity in profile["identities"]]

    return {
        "profiles": len(profiles),
        "identities": len(identities),
        "described": described,
        "deliberatelyEmpty": deliberately_empty,
        "undescribed": len(profiles) - described - deliberately_empty,
        "commandSetStatuses": status_counts([status for command_set in command_sets for status in marked_statuses(command_set)]),
        "identityStatuses": status_counts([identity.get("verification", {}).get("status", "documented") for identity in identities]),
    }


# One plain sentence for each capability kind, for the page's legend.
CAPABILITY_EXPLANATIONS = {
    "onOff": "Switches a load on and off.",
    "dimmable": "Dims a load to a level between off and full.",
    "modem": "A modem, which connects a computer or app to the Insteon network, such as a PowerLinc Modem, a USB Adapter or the modem inside a Hub.",
    "hub": "A Hub, whose modem is driven through the Hub's local HTTP interface.",
    "hubPro": "A Hub Pro, which also has its own HTTP interface for adding and removing devices and updating its software.",
    "thermostat": "A thermostat, with the mode values it reports.",
    "groupEvents": "Sends commands to its ALL-Link groups, and the catalog says what each one means, such as opened or closed.",
    "heartbeat": "Sends a periodic heartbeat to a group, so software can notice a product that has gone quiet.",
}

# How each radio is explained, and the profiles that state none.
RADIO_EXPLANATIONS = {
    "powerline": "Communicates over the home's power wiring only.",
    "rf": "Communicates by radio only.",
    "dual": "Communicates over both the power wiring and radio.",
    "unstated": "No source the catalog cites states how the product communicates.",
}

BATTERY_EXPLANATION = "Runs on batteries and sleeps between messages."

# What each engine means for software, as the schema describes it.
ENGINE_EXPLANATIONS = {
    "i1": "An engine that does not support Enter Linking Mode, so a person uses the device's controls to link it.",
    "i2": "An engine that takes Enter Linking Mode as a standard message.",
    "i2cs": "An engine that rejects an extended message whose D14 checksum is wrong, and takes Enter Linking Mode as an extended message with a checksum.",
}

RADIO_LABELS = {"powerline": "Powerline", "rf": "RF", "dual": "Dual-band"}
ROLE_LABELS = {"controller": "Controller", "responder": "Responder", "both": "Controller and responder"}

# The facts a card gives about a command set, in the order it gives them.
COMMAND_SET_FACTS = ("operatingFlags", "extendedSettings", "standardCommands", "extendedCommands", "serialCommands", "readings")


def capability_section(profiles):
    """The page's legend: what each capability, radio, power source and engine means, and how many
    profiles have it, counted from the data."""

    def number(metric, value):
        return f'<span data-metric="{metric}">{value}</span>'

    def term(label, metric, count, sentence):
        return (
            f"<dt>{html.escape(label)} "
            f'<span class="count-inline">{number(metric, count)} {"profile" if count == 1 else "profiles"}</span></dt>'
            f"<dd>{html.escape(sentence)}</dd>"
        )

    def count(test):
        return sum(1 for profile in profiles if test(profile))

    capabilities = "".join(
        term(CAPABILITY_LABELS[kind], f"capability-{kind}", count(lambda p, k=kind: any(c["kind"] == k for c in p["capabilities"])), sentence)
        for kind, sentence in CAPABILITY_EXPLANATIONS.items()
    )
    power = term("Battery powered", "battery", count(lambda p: p.get("batteryPowered", False)), BATTERY_EXPLANATION)
    radios = "".join(
        term(RADIO_LABELS.get(radio, "Radio not stated"), f"radio-{radio}", count(lambda p, r=radio: p.get("radio") == r if r != "unstated" else "radio" not in p), sentence)
        for radio, sentence in RADIO_EXPLANATIONS.items()
    )
    engines = "".join(
        term(ENGINE_LABELS[engine], f"engine-{engine}", count(lambda p, e=engine: any(entry["engine"] == e for entry in p.get("engines", []))), sentence)
        for engine, sentence in ENGINE_EXPLANATIONS.items()
    )

    return (
        '<section class="capabilities" aria-labelledby="capabilities-heading">'
        '<h2 id="capabilities-heading">What the filters mean</h2>'
        '<p class="note">Each term below is a filter on the products. The count is how many profiles carry it, taken from the catalog\'s data. '
        "Open a card's \"What the catalog describes\" section to see what the catalog holds for that device.</p>"
        '<div class="legend">'
        f"<div><h3>Capabilities</h3><dl>{capabilities}</dl></div>"
        f"<div><h3>Radio and power</h3><dl>{radios}{power}</dl></div>"
        f"<div><h3>Engines</h3><dl>{engines}</dl></div>"
        "</div></section>"
    )


def count_noun(count, singular, plural=None):
    return f"{count} {singular if count == 1 else plural or singular + 's'}"


def command_set_facts(command_set):
    """What a command set covers: (fact, counted phrase, labels) for each part it holds."""
    settings = command_set.get("extendedSettings") or {}
    parts = {
        "operatingFlags": ("operating flag", command_set.get("operatingFlags", [])),
        "extendedSettings": ("extended setting", settings.get("values", [])),
        "standardCommands": ("standard command", command_set.get("standardCommands", [])),
        "extendedCommands": ("extended command", command_set.get("extendedCommands", [])),
        "serialCommands": ("serial command", command_set.get("serialCommands", [])),
        "readings": ("reading", command_set.get("readings", [])),
    }
    named = {"operatingFlags", "extendedSettings", "readings"}
    found = []

    for name in COMMAND_SET_FACTS:
        noun, entries = parts[name]

        if not entries:
            continue

        phrase = count_noun(len(entries), noun) + (" set per button" if name == "extendedSettings" and settings.get("perButton") else "")
        found.append((name, phrase, [entry["label"] for entry in entries] if name in named else []))

    return found


def group_number(value):
    return int(value, 16)


def capability_detail(profile, command_sets):
    """The card's "What the catalog describes" list: what the profile and its command sets state,
    and a plain line where the catalog holds nothing."""
    escape = html.escape
    items = []

    def fact(name, text):
        items.append(f'<li data-fact="{name}">{escape(text)}</li>')

    fact("radio", f"Radio: {RADIO_LABELS[profile['radio']]}." if "radio" in profile else "Radio: the catalog does not state how it communicates.")
    fact("role", f"Role: {ROLE_LABELS[profile['role']].lower()}." if "role" in profile else "Role: the catalog does not state it.")

    if profile.get("batteryPowered"):
        fact("battery", "Battery powered.")

    engines = [engine_note(entry)[0] for entry in profile.get("engines", [])]
    fact("engine", f"Engine: {', '.join(dict.fromkeys(engines))}." if engines else "Engine: the catalog does not state it.")

    groups = profile.get("groups", [])
    roles = {"controller": "controller", "responder": "responder", "both": "controller and responder"}
    fact(
        "groups",
        f"{count_noun(len(groups), 'ALL-Link group')}: " + ", ".join(f"{group_number(group['number'])} {group['name']} ({roles[group['role']]})" for group in groups) + "."
        if groups
        else "The catalog lists no ALL-Link groups for this device.",
    )

    for capability in profile["capabilities"]:
        if capability["kind"] == "groupEvents":
            events = ", ".join(f"{event['event']} (group {group_number(event['group'])}, command {event['command1']})" for event in capability["events"])
            fact("events", f"Reports: {events}.")
        elif capability["kind"] == "heartbeat":
            interval = f" every {count_noun(capability['intervalMinutes'], 'minute')}" if "intervalMinutes" in capability else ""
            fact("heartbeat", f"Heartbeat: group {group_number(capability['group'])}{interval}.")

    entries = list(dict.fromkeys(entry["commandSet"] for entry in profile.get("commandSets", [])))

    if not entries:
        items.append('<li data-fact="noCommandSet">The catalog has no command set for this device.</li>')

    for set_id in entries:
        command_set = command_sets[set_id]
        parts = command_set_facts(command_set)

        if not parts:
            items.append(
                f'<li data-command-set="{escape(set_id)}"><span data-fact="noSettings">The catalog deliberately holds no settings for this device: '
                "there is nothing for software to read or write.</span></li>"
            )
            continue

        lines = "".join(
            f'<li data-fact="{name}">{escape(phrase)}' + (f": {escape(', '.join(labels))}" if labels else "") + ".</li>"
            for name, phrase, labels in parts
        )
        items.append(f'<li data-command-set="{escape(set_id)}">Command set {escape(command_set["name"])}<ul>{lines}</ul></li>')

    return f'<ul class="describes">{"".join(items)}</ul>'


def coverage_section(summary):
    """The page's coverage summary: counts, and a table of statuses."""

    def number(metric, value):
        return f'<span data-metric="{metric}">{value}</span>'

    rows = "".join(
        f'<tr><th scope="row"><span class="status status-{status}">{status.capitalize()}</span></th>'
        f"<td>{html.escape(STATUS_EXPLANATIONS[status])}</td>"
        f'<td class="num">{number(f"commandSet-{status}", summary["commandSetStatuses"][status])}</td>'
        f'<td class="num">{number(f"identity-{status}", summary["identityStatuses"][status])}</td></tr>'
        for status in STATUSES
    )

    return (
        '<section class="coverage" aria-labelledby="coverage-heading">'
        '<h2 id="coverage-heading">What the catalog covers</h2>'
        '<ul class="totals">'
        f'<li><strong>{number("profiles", summary["profiles"])}</strong> profiles</li>'
        f'<li><strong>{number("identities", summary["identities"])}</strong> identities (category, subcategory and firmware a device can report)</li>'
        f'<li><strong>{number("described", summary["described"])}</strong> profiles with a command set</li>'
        f'<li><strong>{number("deliberatelyEmpty", summary["deliberatelyEmpty"])}</strong> profiles that deliberately have none, because there is nothing to read or write</li>'
        f'<li><strong>{number("undescribed", summary["undescribed"])}</strong> profiles with no command set in the catalog, which are gaps</li>'
        "</ul>"
        '<table class="statuses-table"><caption>How sure the catalog is of what it states</caption>'
        '<thead><tr><th scope="col">Status</th><th scope="col">Meaning</th><th scope="col" class="num">Command set values</th><th scope="col" class="num">Identities</th></tr></thead>'
        f"<tbody>{rows}</tbody></table>"
        '<p class="note">A command set value or profile entry with no mark is documented. The command set column counts only values that carry a mark. '
        "The identities column counts every identity. An identity with no mark is counted as documented: it is read from the documents the profile cites, not confirmed on a device.</p>"
        "</section>"
    )


def how_section(version):
    """The page's closing section: where the catalog's facts come from and how to help."""
    base = "https://github.com/brandtdaniels/insteon-device-catalog"

    return (
        '<section class="how" aria-labelledby="how-heading">'
        '<h2 id="how-heading">How this catalog is built and how to help</h2>'
        "<p>Every fact comes from a public Insteon document, cited by its exact title and version in the profile's <code>sources</code>, "
        "or from an observation on a real device, which names the firmware it was seen on. "
        "A value that no document states, that documents disagree on, or that a device has shown carries a status (inferred, conflicting or observed) and a note that say so. "
        "A value with no mark is documented: a public Insteon document gives it.</p>"
        "<p>Help is welcome wherever a value is marked inferred or conflicting, and for devices the catalog has no command set for:</p>"
        "<ul>"
        f'<li>Found a wrong or missing value? <a href="{base}/issues">Open an issue</a> that names the product, the value and the document or device that shows it.</li>'
        f'<li>Own a device? A <a href="{base}/pulls">pull request</a> can record what it did: the model, the firmware it was running and what you saw. '
        f'<a href="{base}/blob/main/README.md#adding-or-changing-a-profile">Adding or changing a profile</a> describes the steps and the checks every change passes.</li>'
        f'<li>Writing software? <a href="{base}/blob/main/API.md">API.md</a> describes the files and how to read them.</li>'
        "</ul>"
        "</section>"
    )


def index_page(profiles, command_sets, version):
    """The landing page: what the catalog is, how to download it, and a card for each profile to
    search and filter."""
    escape = html.escape
    descriptions = capability_descriptions()
    names = {command_set["id"]: command_set["name"] for command_set in command_sets}
    command_sets_by_id = {command_set["id"]: command_set for command_set in command_sets}
    radios = RADIO_LABELS
    roles = ROLE_LABELS
    cards = {}

    def natural(text):
        return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", text)]

    for profile in sorted(profiles, key=lambda profile: natural(profile["model"])):
        category = profile["identities"][0]["category"]
        kinds = [capability["kind"] for capability in profile["capabilities"]]
        aliases = profile.get("aliases", [])
        rows = []

        for identity in profile["identities"]:
            key = (identity["category"], identity["subcategory"])
            code = identity["subcategory"] if identity["category"] == category else f"{identity['category']}/{identity['subcategory']}"
            where = [identity["region"]] if "region" in identity else []

            if "firmware" in identity:
                where.append(f"firmware {identity['firmware']['from']} to {identity['firmware']['through']}")

            settings = [names[entry["commandSet"]] + (" (some firmware)" if "firmware" in entry else "") for entry in profile.get("commandSets", []) if (entry["category"], entry["subcategory"]) == key]
            engines = [engine_note(entry)[0] for entry in profile.get("engines", []) if (entry["category"], entry["subcategory"]) == key]
            rows.append((code, ", ".join(where), ", ".join(settings), ", ".join(engines)))

        # A column every identity shares is shown once, above the table.
        columns = ["Subcategory", "Sold in", "Settings", "Engine"]
        shared = []
        keep = [0]

        for column in (1, 2, 3):
            values = {row[column] for row in rows}

            if values == {""}:
                continue

            if len(values) == 1 and len(rows) > 1 or len(rows) == 1:
                shared.append(f"{columns[column]}: {escape(rows[0][column])}") if rows[0][column] else None
            else:
                keep.append(column)

        table = ""

        if len(keep) > 1 or len(rows) > 1:
            table = "<table><tr>" + "".join(f"<th>{columns[c]}</th>" for c in keep) + "</tr>"
            table += "".join("<tr>" + "".join(f'<td{" class=\"mono\"" if c == 0 else ""}>{escape(row[c])}</td>' for c in keep) + "</tr>" for row in rows)
            table += "</table>"
        else:
            shared.insert(0, f'Subcategory: <span class="mono">{escape(rows[0][0])}</span>')

        # The card shows three lines of the description; a longer one is also given in full here.
        if len(profile.get("description", "")) > 150:
            shared.insert(0, escape(profile["description"]))

        details = (
            '<details class="describes-details"><summary>What the catalog describes</summary>'
            + capability_detail(profile, command_sets_by_id)
            + "".join(f"<p>{line}</p>" for line in shared)
            + table
            + "</details>"
        )

        statuses = [status for status in STATUSES if status in marked_statuses(profile)]
        marks = "".join(f'<span class="status status-{status}" title="{escape(STATUS_EXPLANATIONS[status])}">{status.capitalize()}</span>' for status in statuses)
        facts = [radios[profile["radio"]] for _ in [0] if "radio" in profile]
        facts += [roles[profile["role"]]] if "role" in profile else []
        facts += ["Battery powered"] if profile.get("batteryPowered") else []
        chips = "".join(f'<span class="chip" title="{escape(descriptions.get(kind, ""))}">{escape(CAPABILITY_LABELS.get(kind, kind))}</span>' for kind in kinds)
        search = " ".join([
            profile["model"],
            profile["name"],
            *aliases,
            *(f"{i['category']}/{i['subcategory']}" for i in profile["identities"]),
            *(entry["engine"] for entry in profile.get("engines", [])),
            *(CAPABILITY_LABELS.get(kind, kind) for kind in kinds),
            *([radios[profile["radio"]]] if "radio" in profile else []),
            *([roles[profile["role"]]] if "role" in profile else []),
            *(["battery powered"] if profile.get("batteryPowered") else []),
        ]).lower()
        attributes = {
            "search": search,
            "capabilities": " ".join(kinds),
            "engines": " ".join(sorted({entry["engine"] for entry in profile.get("engines", [])})),
            "radio": profile.get("radio", ""),
            "battery": "true" if profile.get("batteryPowered") else "false",
            "verification": " ".join(statuses),
        }
        data = " ".join(f'data-{key}="{escape(value)}"' for key, value in attributes.items())
        card = (
            f'<article class="card" data-model="{escape(profile["model"])}" {data}>'
            f'<div class="top"><span class="model mono">{escape(profile["model"])}</span><span class="chips">{chips}</span></div>'
            f'<h3>{escape(profile["name"])}</h3>'
            + (f'<p class="aliases">Also known as {escape(", ".join(aliases))}</p>' if aliases else "")
            + (f'<p class="description">{escape(profile["description"])}</p>' if "description" in profile else "")
            + (f'<p class="facts">{" · ".join(facts)}</p>' if facts else '<p class="facts"></p>')
            + (f'<p class="marks"><span class="marks-label">Marked values</span> {marks}</p>' if marks else "")
            + details
            + "</article>"
        )
        cards.setdefault(category, []).append(card)

    categories = sorted(cards)
    sections = []

    for category in categories:
        name = escape(CATEGORY_NAMES.get(category, category))
        description = CATEGORY_DESCRIPTIONS.get(category)
        sections.append(
            f'<section class="category" id="category-{category}" data-category="{category}">'
            f'<h2>{name}<span class="n">{len(cards[category])} product{"" if len(cards[category]) == 1 else "s"}</span></h2>'
            f'<p class="category-code">Category <span class="mono">{category}</span></p>'
            + (f'<p class="category-description">{escape(description)}</p>' if description else "")
            + f'<div class="grid">{"".join(cards[category])}</div></section>'
        )

    kinds = sorted({capability["kind"] for profile in profiles for capability in profile["capabilities"]})
    template = string.Template((ROOT / "templates" / "index.html").read_text())

    return template.substitute(
        version=MAJOR,
        catalog_version=version,
        count=len(profiles),
        coverage=coverage_section(coverage(profiles, command_sets)),
        capabilities=capability_section(profiles),
        how=how_section(version),
        verification_options="".join(
            f'<option value="{status}">{status.capitalize()}</option>' for status in STATUSES if any(status in marked_statuses(profile) for profile in profiles)
        ),
        sections="\n".join(sections),
        category_options="".join(f'<option value="{c}">{escape(CATEGORY_NAMES.get(c, c))}</option>' for c in categories),
        engine_options="".join(
            f'<option value="{e}">{ENGINE_LABELS[e]}</option>'
            for e in ENGINE_LABELS
            if any(entry["engine"] == e for profile in profiles for entry in profile.get("engines", []))
        ),
        capability_options="".join(f'<option value="{k}">{escape(CAPABILITY_LABELS.get(k, k))}</option>' for k in kinds),
    )

if __name__ == "__main__":
    main()
