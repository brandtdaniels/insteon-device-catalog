"""Reads an insteon-observation/1 file and decides whether it may be drafted from.

A rejection says which field is wrong and why, and never repeats the value: the text of a
rejected file may end up in a public place, and what made it fail is the thing that must not.
"""

import datetime
import hashlib
import json
import pathlib
import re

import jsonschema

FORMAT = "insteon-observation/1"
SCHEMA_PATH = pathlib.Path(__file__).resolve().parent / "schemas" / "insteon-observation-1.schema.json"

MAX_FILE_BYTES = 64 * 1024
MAX_CHECKS = 16
MAX_NOTE = 280
MAX_DETAIL = 200

BYTE = re.compile(r"0x[0-9A-F]{2}")
ENGINES = {"i1", "i2", "i2CS"}

# Fields whose text is a value the format defines, so the scan leaves them alone: a key or a
# flag byte can look like an address.
UNSCANNED = {
    "format",
    "device.category",
    "device.subcategory",
    "device.firmware",
    "device.engine",
    "productKey",
    "operatingFlags.raw",
    "observedOn",
}

_BOUNDARY_BEFORE = r"(?<![0-9A-Za-z])"
_BOUNDARY_AFTER = r"(?![0-9A-Za-z])"

ADDRESS = "an Insteon address"
MAC = "a MAC address"
IP = "an IP address"
URL = "a URL or host name"
EMAIL = "an email address"
PATH = "a file path"
SERIAL = "a serial number"

DOTTED_ADDRESS = re.compile(_BOUNDARY_BEFORE + r"[0-9A-Fa-f]{2}\.[0-9A-Fa-f]{2}\.[0-9A-Fa-f]{2}" + _BOUNDARY_AFTER)
# Six hexadecimal digits with a digit among them, or all upper case: an address, not a word such as "decade".
BARE_ADDRESS = re.compile(_BOUNDARY_BEFORE + r"(?=[0-9A-Fa-f]*[0-9])[0-9A-Fa-f]{6}" + _BOUNDARY_AFTER)
BARE_UPPER_ADDRESS = re.compile(_BOUNDARY_BEFORE + r"[0-9A-F]{6}" + _BOUNDARY_AFTER)
MAC_ADDRESS = re.compile(_BOUNDARY_BEFORE + r"[0-9A-Fa-f]{2}([:\-])(?:[0-9A-Fa-f]{2}\1){4}[0-9A-Fa-f]{2}" + _BOUNDARY_AFTER)
IPV4_ADDRESS = re.compile(r"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9])")
IPV6_ADDRESS = re.compile(
    r"(?<![0-9A-Za-z:])(?:(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}|(?=[0-9A-Fa-f:]*::)[0-9A-Fa-f:]{3,39})(?![0-9A-Za-z:])"
)
URL_OR_HOST = re.compile(
    r"(?i)(?:[a-z][a-z0-9+.\-]*://|\bwww\.|\b[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.(?:com|net|org|io|local|lan|home|edu|gov|us|uk|dev|app)\b)"
)
EMAIL_ADDRESS = re.compile(r"[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+")
FILE_PATH = re.compile(r"(?i)(?:^|[\s\"'(=])(?:/[\w.\-]+/|~/|[a-z]:\\|\\\\)")
SERIAL_NUMBER = re.compile(_BOUNDARY_BEFORE + r"(?!0x)(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{8,}" + _BOUNDARY_AFTER)


def load(path):
    """The parsed file and no errors, or None and what is wrong with it."""
    try:
        raw = pathlib.Path(path).read_bytes()
    except OSError:
        return None, ["cannot read the file"]

    if len(raw) > MAX_FILE_BYTES:
        return None, [f"the file is larger than {MAX_FILE_BYTES // 1024} KB"]

    try:
        data = json.loads(raw.decode("utf-8"))
    except UnicodeDecodeError:
        return None, ["the file is not valid JSON: it is not UTF-8 text"]
    except json.JSONDecodeError as error:
        return None, [f"the file is not valid JSON (line {error.lineno}, column {error.colno})"]

    if not isinstance(data, dict):
        return None, ["the file must hold one JSON object"]

    return data, []


def fingerprint(path):
    """Eight hexadecimal digits of the file's content, which name it in output instead of its
    file name: a file name can be an address."""
    try:
        return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()[:8]
    except OSError:
        return "unreadable"


def check(data, models=()):
    """What is wrong with a parsed observation, as plain sentences; empty when it may be drafted from.

    models are the catalog's model numbers: a product name in the file may hold one, which can
    look like an address and isn't."""
    format_problems = _format_problems(data)

    if format_problems:
        return format_problems

    errors = _schema_problems(data)

    if not errors:
        errors += _value_problems(data)

    errors += _privacy_problems(data, set(models))

    return errors


def _format_problems(data):
    value = data.get("format") if isinstance(data, dict) else None

    if value == FORMAT:
        return []

    if isinstance(value, str) and re.fullmatch(r"insteon-observation/\d+", value):
        return [f"unsupported format version; this tool reads {FORMAT}"]

    return [f"not an {FORMAT} file"]


_SCHEMA_VALIDATOR = None


def _validator():
    global _SCHEMA_VALIDATOR

    if _SCHEMA_VALIDATOR is None:
        _SCHEMA_VALIDATOR = jsonschema.Draft202012Validator(json.loads(SCHEMA_PATH.read_text()))

    return _SCHEMA_VALIDATOR


# What each schema rule means, in words that don't repeat the value that broke it.
RULES = {
    "additionalProperties": "has a field the format does not have",
    "type": "has the wrong kind of value",
    "enum": "is not one of the values the format allows",
    "const": "is not the value the format requires",
    "pattern": "is not written the way the format requires",
}


def _schema_problems(data):
    problems = []

    for error in sorted(_validator().iter_errors(data), key=lambda error: error.json_path):
        if error.validator == "required":
            problems.append(f"{error.json_path}: {error.message}")
        else:
            problems.append(f"{error.json_path}: {RULES.get(error.validator, 'does not follow the format')}")

    return problems


def _value_problems(data):
    """The rules the schema leaves open: how identity bytes are written, the engines, the dates
    and the length of free text."""
    problems = []

    for field in ("category", "subcategory", "firmware"):
        value = data["device"][field]

        if value is not None and not BYTE.fullmatch(value):
            problems.append(f"$.device.{field}: is not a byte written as 0x and two upper-case digits")

    engine = data["device"]["engine"]

    if engine is not None and engine not in ENGINES:
        problems.append("$.device.engine: is not one of i1, i2 or i2CS")

    try:
        datetime.date.fromisoformat(data["observedOn"])
    except ValueError:
        problems.append("$.observedOn: not a calendar date")

    if len(data["checks"]) > MAX_CHECKS:
        problems.append(f"$.checks: more than {MAX_CHECKS} checks")

    if len(data.get("note", "")) > MAX_NOTE:
        problems.append(f"$.note: longer than {MAX_NOTE} characters")

    for position, entry in enumerate(data["checks"]):
        if len(entry["detail"]) > MAX_DETAIL:
            problems.append(f"$.checks[{position}].detail: longer than {MAX_DETAIL} characters")

    return problems


def _strings(value, path=""):
    """Every string in the document with its dotted path; list items are written [n]."""
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _strings(item, f"{path}.{key}" if path else key)
    elif isinstance(value, list):
        for position, item in enumerate(value):
            yield from _strings(item, f"{path}[{position}]")


def shapes_in(text, models=(), serial=False):
    """The kinds of private data a string looks like, in a fixed order."""
    shapes = []

    def mentions(pattern):
        return pattern.search(text) is not None

    bare = [match for pattern in (BARE_ADDRESS, BARE_UPPER_ADDRESS) for match in pattern.finditer(text)]

    if mentions(DOTTED_ADDRESS) or any(match.group() not in models for match in bare):
        shapes.append(ADDRESS)

    mac = mentions(MAC_ADDRESS)

    if mac:
        shapes.append(MAC)

    if mentions(IPV4_ADDRESS) or (not mac and mentions(IPV6_ADDRESS)):
        shapes.append(IP)

    if mentions(URL_OR_HOST):
        shapes.append(URL)

    if mentions(EMAIL_ADDRESS):
        shapes.append(EMAIL)

    if mentions(FILE_PATH):
        shapes.append(PATH)

    if serial and mentions(SERIAL_NUMBER):
        shapes.append(SERIAL)

    return shapes


def _privacy_problems(data, models):
    problems = []

    for path, text in _strings(data):
        if path in UNSCANNED:
            continue

        # The product name comes from the catalog, so a model number in it is not an address.
        for shape in shapes_in(text, models if path == "device.model" else (), serial=path == "note"):
            problems.append(f"$.{path}: contains what looks like {shape}; remove it and run the observation again")

    return problems
