"""Finds the catalog entry a change names and sets its verification, and writes profiles the way
the repository keeps them."""

import copy
import json
import pathlib
import re

# What a change may set: the verification of an identity or an engine entry, or of an identity's key.
ENTRIES = {"identity": "identities", "engine": "engines"}
FIELDS = ("verification", "productKeyVerification")
SELECTOR_KEYS = {"identity": {"category", "subcategory", "firmware"}, "engine": {"engine", "category", "subcategory", "firmware"}}
PROFILE_FILE = re.compile(r"devices/([A-Za-z0-9\-]+)\.json")
BYTE = re.compile(r"0x[0-9A-F]{2}")
OBSERVED_NOTE = re.compile(r"Seen on a device running firmware 0x[0-9A-F]{2}: [^\n]+")


def load_catalog(root):
    """Every profile in root/devices, by model."""
    return {path.stem: json.loads(path.read_text()) for path in sorted((pathlib.Path(root) / "devices").glob("*.json"))}


def dump(profile):
    """The text of a profile file: two-space indent, characters as written, one final newline."""
    return json.dumps(profile, indent=2, ensure_ascii=False) + "\n"


def selector_for(entry_kind, entry):
    selector = {key: entry[key] for key in ("engine", "category", "subcategory", "firmware") if key in entry}

    if entry_kind == "identity":
        selector.pop("engine", None)

    return selector


def locate(profile, change):
    """The one entry of the profile the change's selector names, or None."""
    selector = change["selector"]
    found = [
        entry
        for entry in profile.get(ENTRIES[change["entry"]], [])
        if selector_for(change["entry"], entry) == selector
    ]

    return found[0] if len(found) == 1 else None


def change_problems(change):
    """Why a change from a report cannot be trusted, as sentences; empty when it can be applied.

    A report is read by a person and then handed back to apply, so apply accepts only the shape
    drafting writes: a verification set from the observed template and nothing else."""
    if not isinstance(change, dict):
        return ["a change is not an object"]

    problems = []

    if change.get("entry") not in ENTRIES:
        return ["a change names an entry kind apply does not set"]

    if change.get("field") not in FIELDS:
        problems.append("a change names a field apply does not set")

    if change["field"] == "productKeyVerification" and change["entry"] != "identity":
        problems.append("only an identity has a product key verification")

    match = PROFILE_FILE.fullmatch(str(change.get("file")))

    if not match or match.group(1) != change.get("model"):
        problems.append("a change names a file that is not the model's profile")

    selector = change.get("selector")

    if not isinstance(selector, dict) or not {"category", "subcategory"} <= set(selector) <= SELECTOR_KEYS[change["entry"]]:
        problems.append("a change has a selector of the wrong shape")

    after = change.get("after")

    if not isinstance(after, dict) or set(after) - {"status", "note", "firmware"} or after.get("status") != "observed":
        problems.append("a change sets something other than an observed verification")
    elif not OBSERVED_NOTE.fullmatch(str(after.get("note"))) or not after.get("firmware") or not all(
        isinstance(item, str) and BYTE.fullmatch(item) for item in after["firmware"]
    ):
        problems.append("a change's verification does not follow the observed form")

    return problems


def apply_change(profile, change):
    """Sets the change's field on its entry. Returns "applied", "already" when the entry holds the
    result, or a sentence saying why it can't be applied."""
    entry = locate(profile, change)

    if entry is None:
        return "the entry the change names is not in the profile"

    if entry.get(change["field"]) == change["after"]:
        return "already"

    if entry.get(change["field"]) != change["before"]:
        return "the entry does not hold what the report was drafted from"

    field = change["field"]

    if field not in entry and field == "productKeyVerification" and "productKey" in entry:
        # Keep the key's verification next to the key, as the files do.
        items = list(entry.items())
        entry.clear()

        for key, value in items:
            entry[key] = value

            if key == "productKey":
                entry[field] = None

    entry[field] = copy.deepcopy(change["after"])

    return "applied"
