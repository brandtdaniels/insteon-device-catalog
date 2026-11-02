# Conventions

How the catalog names Insteon's products, commands and documents, so profiles and command sets
read the same everywhere. `scripts/build.py` fails on the forms it can check.

## Products

- **Insteon**, never INSTEON.
- A profile's `name` is the product's insteon.com name; its Linc name and other names go in
  `aliases`. A product insteon.com never sold takes the name Insteon's documents give it,
  without "Insteon".
- In prose, **the name, then the model**, without parentheses: Hub 2242, Hub Pro 2243,
  Leak Sensor 2852, PowerLinc Modem 2413U.
- **ICON**, as Insteon's device lists print the product line.

## Protocol

- Engines: **i1, i2, i2CS, i3** in prose. The `engine` value stays `i2cs`.
- **ALL-Link**, **ALL-Link group**, **ALL-Link database**, never "link database" on its own.
- **cleanup**, **SET button**, **on-level**, **ramp rate**, **heartbeat**, **powerline**,
  **dual-band**, and **acknowledgment** in American spelling.
- **Command names** as the Insteon Developer's Guide gives them, such as Get Operating Flags,
  Set Operating Flags, ID Request and Light Status Request. cmd1 `0x2E` is the **extended Get**
  and **extended Set**.
- **cmd1**, **cmd2**, and **D1** through **D14** for user data.
- Bytes as `0x11` with uppercase hexadecimal digits. Group numbers in prose in decimal.

## Documents

Cite each document by its own title, in `sources` and in notes. Insteon published several
editions of the protocol guide and the command tables, so their citations carry the year of the
edition the catalog uses. A product's owner's manual is cited as its name and model, then
Owner's Manual: Hub Pro 2243 Owner's Manual.

| Document | Cite as |
| --- | --- |
| The 2009 protocol guide | Insteon Developer's Guide (2009) |
| The 2007 modem guide | Insteon Modem Developer's Guide |
| The Hub 2242's guide | Insteon Hub Developer's Guide |
| The 2007 command tables | Insteon Command Tables (2007) |
| The device lists | Insteon Device Categories and Product Keys (October 2008), Insteon Device Categories (January 2014) |
| The i2CS notes | Insteon Firmware Update i2CS Developer Notes |
| A product's notes | Its title's subject, then Developer Notes: Leak Sensor Developer Notes |
| HouseLinc's data | HouseLinc Device Definitions (version 2.9.87) |

## How sure a value is

Mark a value that isn't simply documented with `verification`, as the README describes:
`inferred`, `conflicting` or `observed`.

## Spelling and style

American English. Name no third-party projects.
