"""Matches an observation to the catalog and drafts what it can honestly claim.

Drafting writes only verification marks. A value is never changed, and a disagreement is listed
for a maintainer. Every sentence it writes is built from validated fields; the contributor's
free text is shown to the maintainer and goes nowhere else.
"""

import copy

import build

from . import observation, patching

REPORT_FORMAT = "insteon-catalog-ingest-report/1"
NEEDS = "maintainer decision; nothing written"
KNOWN_CHECKS = ("Get Insteon Engine Version", "ID Request", "Product Data Request", "Status Request", "Get Operating Flags")
ENGINES = {"i1": "i1", "i2": "i2", "i2CS": "i2cs"}
ENGINE_LABELS = {"i1": "i1", "i2": "i2", "i2cs": "i2CS"}
NOTHING_ANSWERED = "No check was answered, so this file says nothing about the device. Run `insteon observe` again with the device awake."


def _result(label):
    return {
        "input": label,
        "outcome": "no-change",
        "matched": None,
        "changes": [],
        "unchanged": [],
        "disagreements": [],
        "skipped": [],
        "reportOnly": [],
        "warnings": [],
        "errors": [],
    }


def _disagree(result, code, detail):
    result["disagreements"].append({"code": code, "detail": detail, "needs": NEEDS})


def _firmware_in(identity, firmware):
    low, high = build.firmware_range(identity)

    return low <= int(firmware, 16) <= high


def draft_observation(data, catalog, label="observation"):
    """What an observation that passed check would change in the catalog, and what it contradicts.

    The catalog is updated as changes are drafted, so a second observation sees the first's marks."""
    result = _result(label)
    outcomes = {}

    for check in data["checks"]:
        outcomes.setdefault(check["name"], check["outcome"])

    if set(outcomes) - set(KNOWN_CHECKS):
        result["warnings"].append("A check this tool does not read was ignored.")

    for check in data["checks"]:
        if check["name"] in KNOWN_CHECKS and check["outcome"] != "answered" and check["name"] not in [item["check"] for item in result["skipped"]]:
            result["skipped"].append({"check": check["name"], "reason": f"outcome was {check['outcome']}; says nothing about the device"})

    device = data["device"]
    fields = [device["category"], device["subcategory"], device["firmware"]]

    if outcomes.get("ID Request") != "answered" or None in fields:
        result["warnings"].append(NOTHING_ANSWERED if not any(value == "answered" for value in outcomes.values()) else "The device's identity was not reported, so no profile was matched.")
        _finish(result)

        return result

    category, subcategory, firmware = fields
    matches = [
        (model, identity)
        for model, profile in sorted(catalog.items())
        for identity in profile["identities"]
        if (identity["category"], identity["subcategory"]) == (category, subcategory) and _firmware_in(identity, firmware)
    ]

    if not matches:
        known = any((identity["category"], identity["subcategory"]) == (category, subcategory) for profile in catalog.values() for identity in profile["identities"])

        if known:
            _disagree(result, "firmware-not-covered", f"Category {category}, subcategory {subcategory} is in the catalog, but no identity covers firmware {firmware}. A maintainer decides whether to widen one.")
        else:
            _disagree(
                result,
                "unknown-device",
                f"Category {category}, subcategory {subcategory} and firmware {firmware} match no profile. "
                "A profile needs a name, aliases, an identity, capabilities, an engine and sources, each backed by a public document or an observation.",
            )

        _finish(result)

        return result

    if len(matches) > 1:
        _disagree(result, "ambiguous", f"{len(matches)} profiles claim category {category}, subcategory {subcategory} at firmware {firmware}.")
        _finish(result)

        return result

    model, identity = matches[0]
    profile = catalog[model]
    result["matched"] = {"model": model, "identity": {"category": category, "subcategory": subcategory}}

    if device["model"] is not None and model not in device["model"] and profile.get("name") not in device["model"]:
        result["warnings"].append("The file names a different product than the profile its identity matched.")

    key = data.get("productKey")
    key_sentence = ""

    if key == "none" and "productKey" not in identity:
        key_sentence = " Product Data Request answered and reported no product key."

    _mark(
        result,
        profile,
        "identity",
        identity,
        "verification",
        f"identity {category}/{subcategory}",
        firmware,
        f"ID Request answered with category {category}, subcategory {subcategory} and firmware {firmware}.",
        key_sentence,
    )

    _draft_engine(result, profile, device, outcomes, firmware)
    _draft_key(result, profile, identity, key, firmware)

    if "operatingFlags" in data:
        result["reportOnly"].append(
            {
                "item": "Operating flags",
                "detail": f"The device gave {data['operatingFlags']['raw']}. Not compared with the catalog's flags: the file does not say which request each byte answers.",
            }
        )

    _finish(result)

    return result


def _draft_engine(result, profile, device, outcomes, firmware):
    if outcomes.get("Get Insteon Engine Version") != "answered" or device["engine"] is None:
        return

    category, subcategory = device["category"], device["subcategory"]
    reported = ENGINES[device["engine"]]
    entries = [
        entry
        for entry in profile.get("engines", [])
        if (entry["category"], entry["subcategory"]) == (category, subcategory) and int(firmware, 16) in build.selected_firmware(entry.get("firmware"))
    ]

    if not entries:
        _disagree(result, "firmware-not-covered", f"No engine entry covers category {category}, subcategory {subcategory} at firmware {firmware}; the device reported {device['engine']}.")

        return

    entry = entries[0]

    if entry["engine"] != reported:
        _disagree(result, "engine-differs", f"The device reported {device['engine']}; the catalog gives {ENGINE_LABELS[entry['engine']]} for category {category}, subcategory {subcategory} at firmware {firmware}.")

        return

    _mark(
        result,
        profile,
        "engine",
        entry,
        "verification",
        f"engine {ENGINE_LABELS[reported]} {category}/{subcategory}",
        firmware,
        f"Get Insteon Engine Version answered with {device['engine']}.",
    )


def _draft_key(result, profile, identity, key, firmware):
    if key is None:
        return

    recorded = identity.get("productKey")
    target = f"{identity['category']}/{identity['subcategory']}"

    if recorded is None and key == "none":
        return  # The identity's own note says the device reported no key.

    if recorded is None:
        _disagree(result, "key-not-in-catalog", f"The device reported product key {key}; the catalog gives none for identity {target}. Adding a value is a maintainer decision.")
    elif key == "none" and recorded != "none":
        _disagree(result, "key-not-reported", f"Product Data Request was answered with no key; the catalog gives {recorded} for identity {target}.")
    elif key != recorded:
        _disagree(result, "key-differs", f"The device reported product key {key}; the catalog gives {recorded} for identity {target}.")
    else:
        sentence = "Product Data Request answered and reported no product key." if key == "none" else f"Product Data Request reported product key {key}."
        _mark(result, profile, "identity", identity, "productKeyVerification", f"product key of identity {target}", firmware, sentence)


def _mark(result, profile, kind, entry, field, target, firmware, sentence, extra=""):
    """Records the change that marks the entry's field observed on firmware, or why none is needed."""
    current = entry.get(field)
    selector = patching.selector_for(kind, entry)

    if current is not None and current["status"] == "conflicting":
        _disagree(result, "conflicting-not-overwritten", f"The catalog marks {target} conflicting; an observation does not settle which document is right.")

        return

    if current is not None and current["status"] == "observed":
        listed = current.get("firmware", [])

        if firmware in listed:
            result["unchanged"].append({"target": target, "reason": f"already observed on firmware {firmware}"})

            return

        after = {**current, "firmware": sorted([*listed, firmware])}
        effect = f"added firmware {firmware} to the observed record"
    else:
        note = f"Seen on a device running firmware {firmware}: {sentence}{extra}"

        if current is not None:
            note = f"{note} {current['note']}"

        after = {"status": "observed", "note": note, "firmware": [firmware]}
        effect = f"marked observed on firmware {firmware}"

    change = {
        "file": f"devices/{profile['model']}.json",
        "model": profile["model"],
        "entry": kind,
        "selector": selector,
        "field": field,
        "before": copy.deepcopy(current),
        "after": after,
        "effect": effect,
        "target": target,
    }
    result["changes"].append(change)
    patching.apply_change(profile, change)


def _finish(result):
    if result["changes"]:
        result["outcome"] = "drafted"
    elif result["disagreements"]:
        result["outcome"] = "needs-human"
    else:
        result["outcome"] = "no-change"


def draft_files(paths, catalog, models):
    """The report for observation files, and the contributors' notes in the same order (None where
    a file has none or was rejected). The catalog given is not changed."""
    working = copy.deepcopy(catalog)
    observations = []
    notes = []

    for position, path in enumerate(paths, start=1):
        label = f"observation {position} ({observation.fingerprint(path)})"
        data, errors = observation.load(path)

        if data is not None:
            errors = observation.check(data, models)

        if errors:
            result = _result(label)
            result["outcome"] = "rejected"
            result["errors"] = errors
            notes.append(None)
        else:
            result = draft_observation(data, working, label)
            notes.append(data.get("note"))

        observations.append(result)

    outcomes = [item["outcome"] for item in observations]
    overall = next((name for name in ("rejected", "drafted", "needs-human") if name in outcomes), "no-change")

    return {"format": REPORT_FORMAT, "lane": "observation", "outcome": overall, "observations": observations}, notes


def render_markdown(report, notes):
    """The report as text for the maintainer. The contributor's note appears here and in no
    other output."""
    lines = ["# Observation report", "", f"Outcome: {report['outcome']}", ""]

    for item, note in zip(report["observations"], notes):
        lines += [f"## {item['input']}: {item['outcome']}", ""]

        if item["matched"]:
            identity = item["matched"]["identity"]
            lines += [f"Matched {item['matched']['model']} by category {identity['category']} and subcategory {identity['subcategory']}.", ""]

        sections = (
            ("Errors", [error for error in item["errors"]]),
            ("Proposed changes", [f"{change['file']}: {change['target']}, {change['field']}: {change['effect']}" for change in item["changes"]]),
            ("Already recorded", [f"{entry['target']}: {entry['reason']}" for entry in item["unchanged"]]),
            ("Needs a maintainer decision", [f"{entry['code']}: {entry['detail']}" for entry in item["disagreements"]]),
            ("Not used", [f"{entry['check']}: {entry['reason']}" for entry in item["skipped"]]),
            ("Report only", [f"{entry['item']}: {entry['detail']}" for entry in item["reportOnly"]]),
            ("Warnings", item["warnings"]),
        )

        for title, entries in sections:
            if entries:
                lines += [f"{title}:", ""] + [f"- {entry}" for entry in entries] + [""]

        if note:
            lines += ["Contributor's note (for the maintainer; copied nowhere):", "", f"> {note}", ""]

    return "\n".join(lines).rstrip() + "\n"
