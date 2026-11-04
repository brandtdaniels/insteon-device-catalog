# Working in insteon-device-catalog

Read [CONVENTIONS.md](CONVENTIONS.md), [README.md](README.md) and [API.md](API.md) first. The
conventions set names, spelling and style; the README describes a profile and how sure a value is;
API.md describes what software reads.

## What the catalog is

- **The schema is the Insteon protocol as data.** A profile says what a product is. A command set
  says how it speaks: ALL-Link record data, operating flags, extended settings, commands, the
  flags a linking flow may change and restore, and how a relay holds a state. Software reads these
  fields and carries no code for a device, so a behavior that software needs is a field in
  protocol terms, never a device name.
- **Facts come from hardware observations or public documents cited by exact title and version.**
  Mark every value that isn't simply documented with `verification`: `inferred`, `conflicting` or
  `observed`. An observation names the firmware it was seen on, in the form "Seen on a device
  running firmware 0x41: ...". A value nobody has checked is marked unverified.
- **A field's meaning changes only with a version.** `VERSION` holds the MAJOR.MINOR that software
  matches. A change to a file under `schema/` needs a VERSION bump, and a change that only adds
  data does not. `scripts/check_version.py BASE_SHA` enforces it against a pull request's base.

## How a change goes

1. Say what the change adds and which source backs it.
2. Write the failing test or the failing profile check first (`tests/`, `scripts/build.py`).
3. Add the data or the schema field, then run `python3 scripts/build.py` and
   `python3 -I -m unittest discover -s tests`.
4. One logical change per commit; commit messages carry no attribution lines.
5. Open a pull request. CI must pass on the head commit.
6. A change to data that software acts on needs a hardware test on the head before it is marked
   ready, with the report in the pull request.

## Before pushing

- `python3 scripts/build.py` passes, and `python3 scripts/check_version.py BASE_SHA` passes against the base.
- No em dash or en dash anywhere, in data, docs, commits or pull request text.
- Check `git log -1 --format=%ae` against the identity the repository is configured with before
  every push.
