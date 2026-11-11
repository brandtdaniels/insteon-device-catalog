# The catalog API

The catalog is four static JSON files on GitHub Pages. There's no server, no query
parameters and no authentication: a client downloads the catalog and looks devices up itself.

## Files

Every file is under `https://brandtdaniels.github.io/insteon-device-catalog/v0/` and is fetched
with a plain `GET` over HTTPS.

| File | Contents |
| --- | --- |
| `manifest.json` | The catalog's version, when it was built, the number of profiles, the catalog's file name and its SHA-256 |
| `catalog.json` | Every profile sorted by model, and every command set |
| `device-profile.schema.json` | The JSON Schema every profile follows |
| `command-set.schema.json` | The JSON Schema every command set follows |

`manifest.json`:

```json
{
  "built": "2026-10-28T22:00:00Z",
  "catalog": "catalog.json",
  "devices": 140,
  "sha256": "8d824948278c3c03ffc12ccc994c3f78981de410ebaa3650b174e030de77cfe6",
  "version": "0.4.0"
}
```

`catalog.json`:

```json
{
  "commandSets": [ { "id": "keypadLinc", "name": "KeypadLinc", "…": "…" }, "…" ],
  "devices": [ { "model": "2242", "name": "Hub", "…": "…" }, "…" ]
}
```

## A profile

Bytes are strings of `0x` and two uppercase hexadecimal digits, as Insteon documents write them.

```json
{
  "model": "2852",
  "name": "Leak Sensor",
  "aliases": ["Water Leak Sensor"],
  "description": "Battery-powered sensor that reports when it detects water.",
  "identities": [{ "category": "0x10", "subcategory": "0x08" }],
  "radio": "rf",
  "role": "controller",
  "batteryPowered": true,
  "groups": [
    { "number": "0x01", "name": "Dry", "role": "controller" },
    { "number": "0x02", "name": "Wet", "role": "controller" },
    { "number": "0x04", "name": "Heartbeat", "role": "controller" }
  ],
  "capabilities": [
    {
      "kind": "groupEvents",
      "events": [
        { "group": "0x01", "command1": "0x11", "event": "dry" },
        { "group": "0x02", "command1": "0x11", "event": "wet" }
      ]
    },
    { "kind": "heartbeat", "group": "0x04", "intervalMinutes": 1428 }
  ],
  "sources": ["HouseLinc Device Definitions (version 2.9.87)", "Leak Sensor Developer Notes"]
}
```

`aliases` and `description` are optional, for showing and searching products: other names a
product is known by, and what it is.

An identity can also carry a `firmware` range, `{ "from": "0x40", "through": "0xFF" }`, when a
product reports the same category and subcategory with different behavior across firmware
versions. Without one, the identity covers every version.

An identity's `productKey`, where a source gives it, is the Insteon Product Key the product
reports in D2 to D4 of the Product Data Response that answers Product Data Request (cmd1 `0x03`,
cmd2 `0x00`), written `0x00001A`, D2 first. `none` means the product reports no key: Insteon's
documents mark it Legacy, made before product keys, and such a product doesn't answer Product
Data Request, so an app shouldn't wait for one. Where the catalog is surer or less sure of the
key than of the identity, `productKeyVerification` says so, in the same form as any
`verification`; without it, the identity's `verification` covers the key too.

`engines` says which Insteon engine the product runs under each identity, where a source states
it. Each entry names an `engine` (`i1`, `i2`, or `i2cs`, which rejects an extended message whose
D14 checksum is wrong), an identity's `category` and `subcategory`, and optionally a `firmware`
selection: `{ "only": ["0x41", "0xD1"] }` or `{ "except": ["0x22", "0x24"] }`. Without `firmware`,
every version of the identity runs the engine. For example, the 2476D SwitchLinc Dimmer runs
i2CS, and so expects a checksum in D14 of extended messages, only on the firmware versions its
entries list for each subcategory. A firmware version no entry covers runs an engine the
catalog doesn't know; the build makes sure no two entries cover the same one.

The device itself is the surest source: it reports its engine in reply to a get engine version
command (cmd1 `0x0D`). The catalog's entries are for deciding before asking, or for a device
that doesn't answer.

## A product's lifecycle

A profile's `lifecycle` says how to install the product, link it, wake it, reset it and take it
out of service, so an app can guide a person through each, or do the steps it can itself:

```json
"lifecycle": {
  "linking": { "steps": [
    { "text": "Press and hold the SET button until the switch beeps.",
      "action": "hold", "control": "SET button", "expect": "Beep" } ] },
  "reset": { "steps": [
    { "text": "Pull the SET button out from the switch until the status LEDs turn off.",
      "action": "pullTab", "control": "SET button", "expect": "Status LEDs turn off" },
    { "text": "Wait about ten seconds.", "action": "wait", "seconds": 10 },
    { "text": "Push in and hold the SET button until the long beep stops.",
      "action": "hold", "control": "SET button", "expect": "Long beep" },
    { "text": "Release the SET button.", "action": "release", "control": "SET button", "expect": "Double beep" } ] },
  "resetErases": ["links", "settings"]
}
```

- `installation`, `linking`, `multiLinking`, `unlinking`, `waking`, `reset` and `removal` are each
  a procedure: `steps` in order, with `notes` and a `verification` like any other value.
- A procedure's `alternatives` are other whole procedures for the same thing, such as from a Hub
  instead of with the SET button; an app follows one. Each alternative's `description` names it,
  such as From a Hub or Soft factory reset.
- A step's `text` is what a person reads. `action`, `control`, `seconds`, `count` and `expect`
  say the same in a form an app can use: which button to hold and for how long, how many taps,
  and the beep or LED that shows it worked. Each step does one thing; a step that holds a button
  and then releases it is two steps.
- A step's `device` is `this`, the product the profile describes, unless it says `other`: the
  other device being linked or unlinked, such as the responder a controller links to, or the Hub.
  It defaults to `this`.
- A step's `action` is one of:

  | Action | What the step does |
  | --- | --- |
  | `hold` | Press and hold `control`, for `seconds` or until `expect` happens. |
  | `tap` | Press and release `control` quickly, `count` times. |
  | `press` | Press `control` once, as a click rather than a tap or hold; `seconds`, where given, is how long the press lasts. |
  | `release` | Let go of a held `control`. |
  | `turn` | Turn a knob, dial or other control. |
  | `plugIn`, `unplug` | Plug the product in or unplug it. |
  | `powerOff`, `powerOn` | Turn power off or on, at a breaker or switch, or by unscrewing a bulb and screwing it back in. |
  | `wire` | Connect or disconnect wires. |
  | `mount` | Mount or fasten the product or a part of it. |
  | `insertBatteries`, `removeBatteries` | Put batteries in or take them out. |
  | `pullTab` | Pull something out: the SET button, to open an air gap and cut power, or a battery tab, which may connect the battery. |
  | `wait` | Wait, for `seconds` or until `expect` happens. |
  | `send` | Send the Insteon `command` the step names, by its Insteon Developer's Guide name. |
  | `other` | Anything else, such as choosing a button or removing a cover. |

- Linking with the SET button is written for the device alone: two devices link when one goes
  into linking mode and then the other, and the first becomes the controller.
- Linking and removal can have an alternative described as From a Hub, for adding the product
  to a Hub, or to a modem, and removing it. Its Hub or modem steps are `send` steps: on the
  `other` device for the Hub's own commands, such as Start ALL-Linking, and on `this` device for
  the commands the Hub sends the product, such as Enter Linking Mode or Ping. Steps a person
  takes on the product keep their own actions. A line-powered product is linked as a responder to
  the Hub, so the Hub can control it, and, where its profile lists a group it controls, from that
  group back to the Hub, so the Hub hears it; a battery-powered product is put in linking mode
  first and links to the Hub as a controller. Where its profile says how to keep it awake, the
  steps do so: before linking mode for some products, such as the Wireless Zone Thermostat
  2441ZTH, and right after the Hub starts ALL-Linking for others, such as the Open/Close Sensor
  2843 and the Leak Sensor 2852, which the Hub keeps awake with extended Set. No document
  describes these procedures, so their `verification` says what each is assembled from.
- `linkingTimeoutSeconds` is how long linking mode lasts, `awakeSeconds` how long a woken
  battery device stays awake, and `resetErases` what a factory reset clears.

### Linking from a Hub, as data

`lifecycle.fromHub` says the same as the From a Hub alternative to `linking`, in a form an app
follows without reading its steps:

```json
"fromHub": {
  "legs": [
    { "modem": "controller", "modemGroup": "0x00", "deviceGroup": "0x01" },
    { "modem": "responder", "modemGroup": "0x01", "deviceGroup": "0x01" } ],
  "deviceFirst": false,
  "remoteEnterLinkingMode": { "works": "yes" }
}
```

- `legs` are the links to make, in order, one ALL-Linking session each:
  - a leg with the `modem` as `controller`, so the Hub can control the device, where the device
    has a group that responds;
  - and a leg with the `modem` as `responder` for each group the device controls, so the Hub
    hears every group it sends, such as each keypad button, each thermostat report group or a
    smoke bridge's smoke, carbon monoxide, low battery, malfunction and heartbeat groups.
- `modemGroup` is the group Start ALL-Linking names. `deviceGroup`, one of the profile's groups,
  is the Enter Linking Mode cmd2. On a controller leg, it's the group whose responder record the
  device writes, so it must respond; the build checks it has the role `responder` or `both`, and
  allows a controller leg only where the profile has such a group. On a responder leg, the
  device controls `deviceGroup`, and the modem's record holds that group, so `modemGroup` is the
  same.
- For each leg, the modem starts ALL-Linking first, with link code `0x01` as controller or
  `0x00` as responder, and the device then goes into linking mode, from its SET button or from
  Enter Linking Mode. This is the order seen on an I/O Module 2450 and an Outdoor On/Off Plug
  2634-222 for both roles. The app waits for ALL-Linking Completed (`0x53`) before starting the
  next leg. The build checks each device group against the profile's groups.
- A leg's `allGroupsWhen` names an operating flag state under which the one link puts the
  modem in every group the device controls, such as a sensor's Link to FF Group option
  (`{ "flag": "linkToAllGroups", "set": true }`); otherwise the leg links `deviceGroup` alone,
  and the other groups need links of their own.
- `deviceFirst` is true when a person puts the device in linking mode with its own controls
  before the modem starts ALL-Linking for the first leg, as for a battery-powered sensor or
  remote; the first leg then has the modem as responder. False, the modem starts ALL-Linking
  first for every leg and the device joins.
- `remoteEnterLinkingMode.works` says whether the modem can put the device in linking mode for a
  leg with Enter Linking Mode (cmd1 `0x09`, cmd2 the leg's `deviceGroup`), as a standard message
  to an i2 device and an extended one with a checksum to an i2CS device, in place of its SET
  button: `yes`, `no`, or `unknown`. For `unknown`, an app can ask the device's engine with Get
  Insteon Engine Version (cmd1 `0x0D`), since i1 devices don't support Enter Linking Mode, and
  otherwise has a person use the device's controls.
- `keepAwake`, for a battery-powered device, is the message that keeps it awake through the
  session. Send it `when` it's `beforeLinking`, once a person has woken the device and before it
  goes into linking mode, which needs the device's Insteon ID beforehand, such as from its
  label or an earlier link; or `afterLinked`, right after ALL-Linking Completed gives the
  device's ID, while it's still awake. `release`, where given, lets it sleep again once linking
  is done, and `seconds` is how long `send` keeps it awake, where that's fixed.
- A keepAwake message names a command set entry wherever one exists, so the command set gives
  its bytes, its engine handling and its parameters, such as how many seconds to stay awake and
  their range: `{ "command": "stayAwakeOn" }` for a flag, standard or extended command, or
  `{ "flag": "stayAwake", "set": true }` for an operating flag. Only where no entry exists does
  it give `command1`, `command2` and, for an `extended` one, its fixed `data` bytes and
  `integrity`:

  ```json
  "keepAwake": { "when": "afterLinked", "send": { "command": "stayAwake" } }
  ```

  A message given as bytes also carries the `effect` and `idempotent` a command set entry would,
  as [What a command does](#what-a-command-does) describes. A keepAwake message, named or given
  as bytes, is `configuration` and idempotent; the build fails on one that isn't.

- `fromHub`, each leg, `remoteEnterLinkingMode` and `keepAwake` can carry a `verification`. A
  leg without one is as sure as `fromHub`'s `verification` says. No document describes adding a
  product to a Hub, so most are `inferred`.

## Command sets

Many products share the same settings, so the catalog describes them once, as command sets, and
a profile's `commandSets` entries name the one each identity uses:

```json
"commandSets": [{ "commandSet": "switchLincDimmer", "category": "0x01", "subcategory": "0x20" }]
```

Like an engine entry, a command set entry can carry a `firmware` selection when only some
versions use it. A command set is organized by Insteon's own message types:

- **Operating flags**: bits of the reply to Get Operating Flags (cmd1 `0x1F`), each with the
  `query` that cmd2 asks for and the `bit` that holds it, and the Set Operating Flags (cmd1
  `0x20`) cmd2 values `on` and `off` that set it to 1 and 0. `readings` are queries whose whole
  reply is a value, such as the ALL-Link database's delta, and `flagCommands` are Set Operating
  Flags values with no documented bit to read back.
- **Extended settings**: the `values` in the reply to an extended Get (cmd1 `0x2E`, D2 `0x00`),
  which arrives with `0x01` in D2, each at a `byte` from D3 to D14, and the `writes` that set
  them: an extended Set with the write's `selector` in D2 and its `bytes` from D3. When
  `perButton` is true, D1 chooses the button or group; otherwise D1 is `0x01`.
- **Standard commands**: other standard direct commands, each a `command1` with a fixed
  `command2`, a `parameter` the caller puts in cmd2, or neither for `0x00`. A `reply` is the
  value the acknowledgment carries in cmd2, and `followUp` the value one more direct message
  with the same cmd1 may carry, when the device has it. While the operating flag `extendedWhen`
  names is set, the command goes as an extended message with cmd1 and cmd2 again in D1 and D2
  and the other user data bytes `0x00`. Operating flags and flag commands can carry
  `extendedWhen` too.
- **Extended commands**: other extended direct commands, such as a Get with a cmd2 other than
  `0x00`. Each gives its `command1` and `command2`, its `fixed` user data bytes, the
  `parameters` the caller fills in, its `integrity`, and the extended `reply` that answers it,
  which its `match` bytes tell apart, with the `values` it carries.
- **Serial commands**: for a modem, the commands a host sends over its serial port, as
  [Serial commands](#serial-commands) describes.
- **Direct messages**: standard direct messages the device sends on its own, such as a
  thermostat's reports, each a `command1` with a `value` in cmd2.
- **Notes** on where Insteon's documents disagree, and the `sources` the values come from.

ALL-Link broadcasts aren't in command sets: a profile's `groupEvents` capability says what each
group's commands mean.

A value in a message names where it is: cmd2 in a standard message, or the user data `byte`, or
`bytes` most significant first, in an extended one. Its `mask`, if any, picks out its bits, and
it reads as:

| `kind` | Meaning |
| --- | --- |
| `number` (the default) | A number, two's complement if `signed`, times `scale`, in `unit` |
| `buttons` | One bit per button, button 1 in bit 0 |
| `enumeration` | A name from the command set's `enumerations` entry that `enumeration` names |
| `flags` | The named `bits` |
| `boolean` | True when nonzero |

A `range` gives the values a parameter can take, in its unit. The unit `displayDegrees` means
degrees in the scale the device displays: the command set's `displayScale` names the flag,
value or bit that is true when it displays Celsius. Without one, or before it's been read,
they're Fahrenheit.

`integrity` says how an extended message's user data is protected: `none`, a `checksum` in D14
(the two's complement of the sum of cmd1, cmd2 and D1 through D13), or a `crc`, a 16-bit CRC
over cmd1, cmd2 and D1 through D12, with its high byte in D13 and its low byte in D14. Without
`integrity`, it's `none`.

For example, the reply to Get Operating Flags with cmd2 `0x00` from a device using
`switchLincDimmer` has bit `0x20` set when its key beep is on, and Set Operating Flags with cmd2
`0x0B` turns the beep off. An i2CS device expects these as extended messages with a checksum in
D14.

And a TempLinc Thermostat, which uses `tempLinc`, reports a new temperature with a direct
message whose cmd1 is `0x6E` and whose cmd2 is the temperature in half degrees of the scale it
displays. Its `readStatus` extended command asks for its status, and the reply carries the
temperature in D9 and D10, in tenths of a degree Celsius whatever the display shows.

### Serial commands

A modem is a device like any other, so its profile names a command set in `commandSets` and the
command set describes how it speaks. A modem speaks over its serial port, where a command is
`0x02`, a command number and a payload whose length the number fixes, and the modem answers with
an echo of the command ending in an ACK (`0x06`) or a NAK (`0x15`). A command set's
`serialCommands` describe them:

```json
{ "name": "deleteAllLink", "description": "Deletes the ALL-Link to a device for a group.",
  "effect": "destructive", "idempotent": true, "number": "0x64",
  "fixed": [{ "position": 1, "value": "0xFF" }],
  "parameters": [{ "name": "group", "description": "The ALL-Link group to delete.", "byte": 2 }] }
```

- `number` is the command number, the byte after `0x02`.
- `fixed` and `parameters` number the payload bytes from 1, as an extended command numbers user
  data bytes. Every payload byte is fixed or a parameter, since the number fixes the payload's
  length, so there is no byte left to be `0x00`.
- `reply` gives the values the modem returns after the command number and before the ACK or NAK,
  numbered from 1 as the payload is. A command whose echo only repeats the payload needs none.
- `effect`, `idempotent`, `guard` and `verification` mean what they do for other commands.

Commands that differ only by a control byte, such as the link code of Start ALL-Linking or the
control code of Manage ALL-Link Record, are separate entries told apart by `fixed`, because their
effects differ: one number can be a link, a read and a deletion.

Send Insteon Standard or Extended Message (`0x62`) and Send ALL-Link Command (`0x61`) are frames
that carry a device message, so they are not entries: the command set of the device the message
goes to describes what the frame carries.

A profile names a modem's command set under each identity, as for any product: `modem` for the
2412 and 2413 powerline modems, which the Insteon Modem Developer's Guide describes, and
`hubModem` for the Hub 2242, whose Insteon Hub Developer's Guide adds commands. Where no document
describes a modem's serial commands, its profile names none, and software treats every serial
command it sends as undescribed.

## Settings pages and device controls

A device is addressed by its Insteon ID, but most of what an app shows belongs to one of its
groups: a FanLinc's light and fan, a dual outlet's top and bottom outlets, a keypad's buttons.
The catalog says what each group is and how to show each setting, so an app can build its pages
from the catalog alone.

**Group types.** A command set's `groupTypes` say what its groups can be, and each profile group
names one in `type`, which every command set its identities use must have:

```json
"groupTypes": [
  { "name": "light", "label": "Light", "kind": "dimmer",
    "state": { "command": "readStatus" },
    "actions": [
      { "name": "on", "label": "On", "command": "lightOn" },
      { "name": "off", "label": "Off", "command": "lightOff" } ] },
  { "name": "fan", "label": "Fan", "kind": "fan",
    "state": { "command": "readFanSpeed", "ranges": [
      { "from": "0x00", "through": "0x00", "label": "Off" },
      { "from": "0x01", "through": "0x7F", "label": "Low" },
      { "from": "0x80", "through": "0xFE", "label": "Medium" },
      { "from": "0xFF", "through": "0xFF", "label": "High" } ] },
    "actions": [
      { "name": "off", "label": "Off", "command": "fanOff" },
      { "name": "low", "label": "Low", "command": "fanLow" },
      { "name": "medium", "label": "Medium", "command": "fanMedium" },
      { "name": "high", "label": "High", "command": "fanHigh" } ] }
]
```

```json
"groups": [
  { "number": "0x01", "name": "Light", "role": "both", "type": "light" },
  { "number": "0x02", "name": "Fan", "role": "responder", "type": "fan" }
]
```

- `kind` is `dimmer`, `relay`, `fan`, `sensor`, `button`, `windowCovering`, for a window
  covering or other motorized cover that opens and closes, `alarm` or `arming`.
- `state` names the standard command whose acknowledgment carries the group's state in cmd2.
  With `bitPerGroup`, the reply holds one bit per group, group 1 in bit 0, as a keypad's LEDs or
  a dual outlet's outlets do; `ranges` name ranges of the value, such as a fan's speeds. With
  `onWhen`, the group is on when cmd2 ANDed with its `mask` equals its `value`, and off
  otherwise, as an EZFlora zone is on when the valve status byte names it as the active valve
  with a valve on: `{ "mask": "0x87", "value": "0x81" }` for zone 2.
- `outputs` are parts of the group's load that one command can switch together, such as the
  0-10V Ballast Dimmer 2475DA2's two relays while its `relayMode` flag is set (`activeWhen`).
  Each action whose command takes a parameter, and gives no fixed `value`, selects outputs by
  their `bits` in it: `on` with `0x03` turns both relays on, and `off` with `0x01` turns relay 1
  off.
- An `alarm` group sounds when a linked device triggers it while the device is armed in any of
  its `armModes`, `home` or `away`, and an `arming` group arms the device in all of its
  `armModes`. The Siren 2868-222's groups 1, 3 and 5 are alarms and 2, 4 and 6 arming groups: a
  group On from a controller linked to an arming group arms the siren after a countdown, Fast On
  arms it silently, and a group Off to any arming group disarms it, as its command set's notes
  give.
- `actions` are what an app can tell the group to do, for controls, scenes and schedules. Each
  names a standard or extended command and, when the command takes a parameter, either a fixed
  `value` (`0xFF` to switch a relay on) or nothing, for the caller to give, such as a dimmer's
  level. An action with `schedulable` false stays out of schedules.
- Only a responder can be told to do something, so a group whose type has actions has the role
  `responder` or `both`. A controller-only group, such as a sensor's, has no actions; it's
  something an app watches for, through the profile's `groupEvents`.
- A group with `activeWhen` is in use only while that operating flag is `set` or clear: a
  keypad's detached load, group 9, while `detachedLoad` is set, and its group 1 while it's clear.

**ALL-Link record data.** A group type's `linkData` says what Data 1 to 3 hold in the ALL-Link
database records for the group, so an app adding it to a scene writes the right bytes:

```json
"linkData": { "responder": [
  { "byte": 1, "name": "onLevel", "label": "On-level", "description": "The level the load goes to.",
    "unit": "percent", "scale": 0.392157, "range": { "from": "0x00", "through": "0xFF" } },
  { "byte": 2, "name": "rampRate", "label": "Ramp rate", "description": "How fast it gets there.",
    "table": "rampRate" },
  { "byte": 3, "name": "button", "label": "Button", "description": "The button the record is for.",
    "perGroup": true } ] }
```

- `responder` describes the record in the responder: the state the group goes to when its
  controller's group command arrives. `controller` describes the controller's record, where a
  product documents one; otherwise its data bytes don't matter.
- Each byte carries a `range`, a `unit` and `scale` or a `table`, as settings do, a fixed `value`
  to write, or `perGroup`. With `perGroup`, the byte is the responder's own group: the button or
  part of the device the record is for, as the profile numbers it. It isn't the record's Group
  field, which holds the controller's group.
- Relays and button LEDs use the `onOff` table: `0x00` off, `0xFF` on.
- A byte a list leaves out has no documented use for the group; write `0x00`.
- A device linked with its SET button keeps its present state as the record's data, so a light
  should be at the level wanted when it's linked.

A modem writes records of its own when it links, and its profile's `modem` capability can say
what their Data 1 to 3 hold, in `linkData`, so an app that writes such a record by hand writes
the same bytes:

```json
{ "kind": "modem", "linkData": { "controller": [
  { "byte": 1, "name": "data1", "description": "Always 0x01 in the records seen.", "value": "0x01" },
  { "byte": 2, "name": "subcategory", "description": "The responder's subcategory.", "identity": "subcategory" },
  { "byte": 3, "name": "firmware", "description": "The responder's firmware version.", "identity": "firmware" } ] } }
```

- `controller` is for the records in which the modem is the controller, and `responder` for
  those in which it's the responder.
- Each byte gives either a fixed `value` or the `identity` byte it copies: the linked device's
  `category`, `subcategory` or `firmware`, as ALL-Linking Completed reports them.
- A byte a list leaves out isn't known.

**Whether a relay holds its state.** A `relay` group type's `stateHolding` says which of the
command set's operating flags decide whether the relay holds the state a command switches it to.
Its flag names are the command set's own `operatingFlags` names, and the build fails on one that
isn't there. The I/O Linc's relay:

```json
"stateHolding": {
  "releasedBy": ["momentary"],
  "restState": "off",
  "pulsesOnEveryCommandWhen": [["momentary", "momentaryOnBothCommands"]] }
```

- `releasedBy` lists flags any one of which, while set, keeps the relay from holding a
  commanded state: it returns to `restState` by itself after a time, as a momentary relay
  does.
- `restState` names the group type's action whose state the relay returns to, here `off`.
- `pulsesOnEveryCommandWhen` lists sets of flags. While every flag of any one set is set, each
  group On and each group Off pulses the relay whatever the responder record's data holds, so
  a state recorded at link time means nothing.

A relay that no flag releases has an empty `releasedBy`, and always holds the state it's switched
to. Its `restState` still names its resting action, and it has no `pulsesOnEveryCommandWhen`;
the build fails on one. The SwitchLinc Relay's load:

```json
"stateHolding": {
  "releasedBy": [],
  "restState": "off" }
```

An app evaluates it from the flags it last read from the device. With no `releasedBy` flag set,
the relay holds the state it's switched to, so with `releasedBy` empty it needs to read none. With one set, it doesn't, and it ends in
`restState`. With every flag of a `pulsesOnEveryCommandWhen` set also set, a recorded state
means nothing either. A flag the app hasn't read leaves the answer unknown. A group type without
`stateHolding` says nothing about it, so an app assumes neither that the relay holds a state nor
that it releases one.

**Settings.** Operating flags, readings and extended settings values can carry:

- `label`: what to call the setting, such as "Beep on button press".
- `section`: the heading to show it under, one of Load, Relay, Sensor, Buttons, LEDs, Night,
  Timer, Alarm, Display, Battery, Linking, Communication, X10 and Diagnostics, in that order.
- `advanced`: true for a setting to keep out of sight unless asked, such as the powerline's
  timing or X10.
- `default`: the value as the device leaves the factory, where a document gives it: true or
  false for a flag, a byte for a value.
- For a value, `unit` and `scale` to show it as a number, such as an on-level as a percentage,
  or `table`, the command set's `valueTables` entry that names each raw value, such as the ramp
  rate's durations. A table can carry a `verification` like any other value.

The control follows from the setting:

- A flag with both `on` and `off` is a switch. A flag set by standard commands instead names them
  in `onCommand` and `offCommand`, such as the i3 products' night mode. A flag with only one of
  them can be set only that way, such as the Siren's disarmed flag, which the arm command clears.
  Any other flag, and every reading, is read-only.
- A value with a `table` is a picker, a `buttons` value is a choice of buttons, and a value with a
  `range` is a slider or stepper. A value is writable when an extended settings write sets it, or
  when it names the extended command that does in `write`; otherwise it's read-only.
- A value is per group when the write that sets it is `perButton`; everything else is the whole
  device's.

**Flags an app must guard.** Some operating flags can cut a device off or lock it, so their
`guard` says how a write treats them:

- `keep`: a write leaves the bit as it was read. Radio off, powerline off and checksum required
  have it. Each carries `default` where its command set's sources give the factory state, so
  software can report a device whose bit differs from it; the build requires it everywhere a
  source gives one.
- `keep` also covers the Thermostat Adapter 2441V's extended commands only flag: it changes
  the message form the adapter accepts, as checksum required does, so an app that flips it
  stops being understood.
- `neverSet`: a write may clear the bit but never sets it. The programming lock has it.

A Set Operating Flags command (cmd1 `0x20`) that turns radio off, powerline off, checksum
required or the programming lock on has `guard` `never`, whether it's in `flagCommands`,
`standardCommands` or `extendedCommands`: an app never sends it. The build finds these by name
and by the cmd2 they send, matched against the command set's own flags and on-commands. And where an extended command writes operating flags as a `flags` parameter,
such as the i3 products' `writeProperties`, each guarded bit carries the same `guard`, so an app
fills it from the device's last report. The build requires these guards wherever those flags
appear.

Some extended settings values are the same byte as an operating flags reply, such as the
Open/Close Sensor's `configuration` and the Hidden Door Sensor's `operatingFlags`. Such a value's
`flagsQuery` names the Get Operating Flags query (cmd2) whose reply it is, `0x00` for both, and
the command set's operating flags with that query name its bits. Before writing the value, an
app reads it, and refuses a write that would change a `keep` bit or set a `neverSet` one.

**Flags linking changes.** A flag can change what a link records, or linking can change the
flag itself. A command set's `linkingChanges` lists the flags a linking flow may change around
a link, as an allowlist: it reads them before it links and sets them back afterward with Set
Operating Flags, and it changes no other flag. No flag with a `guard` is ever on the list. A
flag goes on the list once a document or a device shows that linking changes it or that it
changes what a link records; until then a command set has no `linkingChanges`.

```json
"linkingChanges": [{ "flag": "exampleFlag" }]
```

## What a command does

Every flag command, standard command, extended command and serial command carries an `effect` and
`idempotent`, so software decides from the catalog whether a message needs a person's consent
and whether it may be sent again:

```json
{ "name": "lightOn", "description": "Turns the load on to the level in cmd2 at the saved ramp rate.",
  "effect": "actuation", "idempotent": true, "command1": "0x11", "parameter": { "…": "…" } }
```

`effect` says what the message does to its addressee, the device or modem it's sent to:

| `effect` | The message |
| --- | --- |
| `readOnly` | Asks for state. The addressee answers, with an acknowledgment's cmd2, an extended reply, or a direct or broadcast report such as a database checksum, and changes nothing it keeps or does, apart from state that matters only to the request, such as the address Peek One Byte reads. |
| `configuration` | Changes a setting the addressee keeps and acts on later, such as operating flags, extended Set values, setpoints, timers or registers, and nothing it does at once. |
| `link` | Puts the addressee in or out of ALL-Linking mode, or adds an ALL-Link record. |
| `actuation` | Changes what the addressee does at once: a load, an output, a valve, a sound, a program, or a group broadcast from the addressee. |
| `destructive` | Removes or overwrites ALL-Link records, memory or counters, restores factory settings, or leaves the addressee unable to communicate with the modem until a person acts. |

`idempotent` is true when sending the identical message twice leaves the addressee in the same
state as sending it once, as for a command that sets a level or a value. It's false for a
relative step, such as Brighten One Step or a setpoint raise, for a start that restarts, such as
Start Manual Change or a program start, and for a toggle.

The rest of a command set takes its effect from where it sits, so it carries no field of its own:

| Item | Effect |
| --- | --- |
| An operating flag's `on` and `off` | `configuration`, idempotent: Set Operating Flags with a fixed cmd2. Its `guard` decides whether an app writes it. |
| An extended settings write | `configuration`, idempotent: an extended Set writes absolute bytes. `flagsQuery` and guards decide what it may change. |
| A group type's `actions` | The effect of the command each names, which the build requires to be `actuation`. |
| A group type's `state` | The effect of the command it names, which the build requires to be `readOnly`. |
| A flag's `onCommand` and `offCommand`, and a value's `write` | The effect of the command each names, which the build requires to be `configuration`. |
| `linkingChanges` | `configuration`, under the link operation that changes them. |
| A keepAwake message | The named command's or flag's effect, or its own `effect` when given as bytes; the build requires `configuration` and idempotent. |
| A lifecycle `send` step | None: it names a command for a person, by its Insteon Developer's Guide name. |

The build also requires:

- that a command with `guard` `never` is `destructive`;
- that a serial command's number isn't `0x61` or `0x62`, every payload byte is fixed or a
  parameter exactly once, entries with one number have one payload length, and no two entries
  send the same number and fixed bytes;
- that no Set Operating Flags command (a flag command, or cmd1 `0x20`), no extended Set (cmd1
  `0x2E`, cmd2 `0x00`, a fixed D2 other than `0x00` or a D2 the caller gives), no properties
  write (cmd1 `0x2E`, cmd2 `0x01`, D1 `0x02`) and no write with cmd1 `0x2F` and D2 `0x02` is
  `readOnly`, and that a `readOnly` command is idempotent;
- that entries one message can match have the same effect and `idempotent`: Set Operating Flags
  entries sending the same cmd2, such as a flag and a standard command with cmd1 `0x20`, and
  extended commands whose bytes can all agree, as [Reading effects](#reading-effects) matches
  them;
- that no `readOnly` extended command matches every message a command with another effect does;
- that serial commands one frame can match (the same number, and no fixed byte that differs)
  have the same effect and `idempotent`, and that no `readOnly` serial command matches every
  frame a command with another effect does;
- and that a keepAwake message given as bytes has the effect of a standard or extended entry
  with the same bytes.

An effect never stands in for a guard: a destructive command that turns a guarded flag on needs
`guard` `never` as well.

### Reading effects

Software finds a message's effect by its bytes, not by the name it was sent under:

- A standard command matches by cmd1 and its fixed cmd2, or any cmd2 its parameter allows.
- An extended command matches by cmd1, cmd2 and every user data byte. A byte in `fixed` must
  hold its value; a byte a parameter fills, D1 of a `perButton` command and the integrity bytes
  (D14 for a checksum, D13 and D14 for a CRC) can hold any value; and every other byte must be
  `0x00`, as the schema says of the rest. A message with a nonzero byte where an entry expects
  `0x00` doesn't match that entry.
- A flag command or an operating flag's `on` or `off` matches by cmd1 `0x20` and cmd2, sent as a
  standard or an extended message.
- An extended settings write matches by cmd1 `0x2E`, cmd2 `0x00` and its selector in D2.
- A command sent in its `extendedWhen` form, an extended message with its cmd1 and cmd2 again in
  D1 and D2 and the other user data bytes `0x00` apart from integrity, matches the standard
  command or flag command it's the form of, as if it had been sent as a standard message.

- A serial command matches a frame by its command number and every fixed payload byte; a
  payload byte a parameter fills can hold any value.

It reads them so that anything it can't place fails closed:

1. An entry without an `effect`, or with a value the software doesn't know, is `destructive`.
2. An entry without `idempotent` isn't idempotent.
3. A message no entry describes is undescribed: neither readOnly nor any other effect, and sent
   only by an operation that sends bytes a person typed.
4. A device without a command set has every message undescribed, apart from those whose effect
   the protocol itself fixes, such as Ping and ID Request. So does a modem without one, for every
   serial command.
5. A message several entries describe takes the strictest of their effects, and is idempotent
   only if all of them are.
6. A downloaded catalog that gives a command known from the copy the software ships a weaker
   effect, or turns its `idempotent` from false to true, is refused, and the shipped copy kept.
   `readOnly` is weakest and `destructive` strictest; a change among `configuration`, `link` and
   `actuation` counts as weaker too.

A message without an acknowledgment may have reached the device, so software sends it again only
when it's idempotent. A modem's NAK means the message never left the modem, so it can always be
sent again.

## Keeping a copy up to date

1. Fetch `manifest.json`.
2. If its `version` isn't one the client understands, keep the copy it has: below 1.0, one
   with the same MAJOR.MINOR as the client was built for; from 1.0, the same MAJOR.
3. If its `sha256` matches the copy the client has, stop: nothing changed.
4. Otherwise fetch `catalog.json`, check that its bytes hash to `sha256`, and only then replace
   the copy.

Ship a copy with the software, so it works offline and fetching is optional.

## Looking a device up

1. Ask the device to identify itself. Its reply carries its category, subcategory and firmware
   version.
2. Find the profile with an identity whose `category` and `subcategory` match and whose
   `firmware` range, if it has one, includes the firmware version. The build makes sure no two
   identities overlap, so there's at most one.
3. With no match, fall back on what the category alone implies, such as dimming for category
   `0x01` and switching for `0x02`.

Example: a device replies with category `0x10`, subcategory `0x08`. That's the 2852 Leak
Sensor above, so an ALL-Link broadcast from it with cmd1 `0x11` to group `0x02` means `wet`, and
not hearing from it for longer than its 1428-minute heartbeat interval means it may have stopped
working.

## Versions

The catalog follows semantic versioning, MAJOR.MINOR.PATCH, and the path names its MAJOR version:
`v0` now, `v1` once the format is final. The manifest carries the version and when the catalog
was built; the catalog itself doesn't, so its SHA-256 changes only when its data does.

- PATCH: the data changed but not the format, such as a new profile or a corrected value. The
  publishing workflow counts it: the commits since `VERSION` last changed that changed
  `devices/` or `commandSets/`.
- MINOR: the format changed, in the schemas or in the files' layout. From 1.0, only by adding
  optional fields a client can ignore.
- MAJOR: from 1.0, a change that would break a client built for the earlier format. It will be
  published under a new path, with the earlier MAJOR's files kept beside it.

Below 1.0 the format can still change in any MINOR, so a client should only take a catalog with
the MAJOR.MINOR it was built for. `VERSION` in the repository holds MAJOR.MINOR; the build fails
a pull request that changes the schemas without raising it, or that lowers it. A change to the
files' layout in `scripts/build.py` must raise it too.
