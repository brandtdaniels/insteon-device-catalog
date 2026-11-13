# Insteon Device Catalog

[![Catalog](https://github.com/brandtdaniels/insteon-device-catalog/actions/workflows/catalog.yml/badge.svg?branch=main)](https://github.com/brandtdaniels/insteon-device-catalog/actions/workflows/catalog.yml)
[![Device profiles](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fbrandtdaniels.github.io%2Finsteon-device-catalog%2Fv0%2Fmanifest.json&query=%24.devices&label=device%20profiles)](https://brandtdaniels.github.io/insteon-device-catalog/v0/catalog.json)
[![Catalog version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fbrandtdaniels.github.io%2Finsteon-device-catalog%2Fv0%2Fmanifest.json&query=%24.version&label=catalog)](https://brandtdaniels.github.io/insteon-device-catalog/v0/manifest.json)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

What each Insteon product is and what it can do, as data, so software can support a device by
looking it up instead of carrying code for it.

Each product has a profile in [`devices/`](devices), named by its model number. A profile lists:

- **Name, aliases and description:** the product's name, other names it's known by, and what
  it is.
- **Identities:** the category and subcategory the product reports when asked to identify
  itself, the firmware versions they cover where those matter, and its product key where a
  source gives one.
- **Radio and role:** where a source states them, how it communicates (powerline, RF or both), and whether it can be an
  ALL-Link controller, a responder, or both.
- **Groups:** its ALL-Link groups, and whether software must link a group.
- **Capabilities:** what it can do, chosen from a fixed set: `onOff`, `dimmable`, `modem`,
  `hub`, `hubPro`, `thermostat`, `groupEvents` and `heartbeat`. A capability is a description,
  never code.
- **Engines:** where a source states it, the Insteon engine (i1, i2 or i2CS) the product runs
  under each identity and firmware version.
- **Command sets:** where a source states it, the command set the product uses under each
  identity: its operating flags, extended settings, other standard and extended commands, a
  modem's serial commands, and the direct messages it sends, which [`commandSets/`](commandSets) describes once for every
  product that shares them.
- **Lifecycle:** how to install the product, link and unlink it, wake it, reset it and take it
  out of service, as steps a person or an app follows.
- **Sources:** the documents its values come from.

[`schema/device-profile.schema.json`](schema/device-profile.schema.json) and
[`schema/command-set.schema.json`](schema/command-set.schema.json) define the formats.

## Using the catalog

Every change to `main` publishes the profiles to GitHub Pages:

- `https://brandtdaniels.github.io/insteon-device-catalog/v0/catalog.json`: every profile,
  sorted by model, and every command set
- `https://brandtdaniels.github.io/insteon-device-catalog/v0/manifest.json`: the catalog's
  version, when it was built, the number of profiles and the catalog's SHA-256
- `https://brandtdaniels.github.io/insteon-device-catalog/v0/device-profile.schema.json` and
  `command-set.schema.json`: the schemas
- `https://brandtdaniels.github.io/insteon-device-catalog/`: a page listing the files and every
  profile, for people rather than software

See [API.md](API.md) for the files' formats, how to keep a copy up to date and how to look a
device up. In short: read the manifest first, check that its version is one you understand, then
download the catalog and check its hash. The catalog follows semantic versioning, and the path
names its MAJOR version; it stays at 0 until the format is final. Software should ship a copy of
the catalog and treat downloading a newer one as optional.

## Adding or changing a profile

1. Add or edit `devices/<model>.json`. Check every value against a document, and list the
   document in `sources`. Each string in `sources` is a document's exact title as registered in
   [`documents/registry.json`](documents/registry.json); to cite a document the catalog hasn't
   cited yet, add an entry there first (`title` and `kind`, plus `edition` and a public `url`
   where you know them). The registry is for the repository's checks and isn't published.
2. Run `pip install -r requirements.txt` and `python3 -I scripts/build.py` to validate. It checks
   each profile against the schema, that the file is named for its model, that no capability
   appears twice, that no two profiles claim the same identity for the same firmware, that every `sources` string is a registered document, and that
   each engine and command set entry names one of the product's identities and no firmware
   version twice. It also checks each command set in `commandSets/` against its schema, and that
   no two of its flags share a bit or a command, no two values share a byte, no two writes
   share a selector, no two commands or direct messages share a command, no message fills a
   byte's bits twice, every flag and enumeration it names exists, and each command's `effect`
   and `idempotent` fit what the protocol and the command set say about it, as
   [API.md](API.md#what-a-command-does) describes. A change to
   `scripts/build.py` comes with a test in `tests/`; run them with
   `python3 -I -m unittest discover -s tests`.
3. Follow [CONVENTIONS.md](CONVENTIONS.md) for names, terms and citations; the build fails on
   the forms it rules out.
4. Open a pull request. CI runs the same check.

### Lifecycle steps

Write each procedure in `lifecycle` as the product's documents give it, one action per step: a
step that holds the SET button and then releases it is two steps. Mark a step done on the other
device being linked with `"device": "other"`. Put another way of doing the same thing, such as
from a Hub, in the procedure's `alternatives`, with a `description` that names it. A Hub's
commands are `send` steps naming their Insteon `command`: the Hub's own commands, such as Start
ALL-Linking, are on the `other` device, and the commands the Hub sends the product, such as Enter
Linking Mode or Ping, are on `this` one. [API.md](API.md#a-products-lifecycle)
lists every `action`.

Give the same as data in `lifecycle.fromHub`: the links to make with the Hub's modem, in order,
whether the product goes into linking mode first, whether the modem can put it there with Enter
Linking Mode, and, for a battery-powered product, how to keep it awake. Keep a From a Hub note
only where it says more than that data does. The build checks each link's device group against
the profile's groups.

### How sure a value is

A value with no `verification` is documented: an Insteon document gives it, and none of the
catalog's sources disagree. Where that isn't so, give the profile, identity, product key (`productKeyVerification`, where it differs from the identity's), engine, command set entry, group, lifecycle procedure, `fromHub` or its legs,
remote Enter Linking Mode or keep-awake message, or modem link data byte, or the command set's
flag, reading, value, write, field, command or direct message, value table, group type, state
`onWhen`, outputs, link data byte or `linkingChanges` entry, a `verification` with a `status`
and a `note`:

| Status | Meaning | The note says |
| --- | --- | --- |
| `documented` | An Insteon document gives the value, as when `verification` is omitted. | What more there is to know about the source. |
| `inferred` | No document states it. | What it's read from: an example, a similar product, or how the product behaves. |
| `conflicting` | Insteon's documents disagree. | What each document gives, and which value the catalog uses. |
| `observed` | Seen on a device. | What was seen. List the firmware versions the device was running in `firmware`. |

```json
"verification": {
  "status": "conflicting",
  "note": "The 2472D Developer Notes give 0x63 as the default over-temperature limit; the <other document's title> gives 0x7D. The catalog uses 0x63."
}
```

An app can warn before it sends a command, or trusts a reading, whose status is `conflicting`
or `inferred`. When a device shows a value, change its status to `observed`.
