## What changes

<!-- The data or schema change, and the source that backs it: a hardware observation (device and
firmware) or a public document by exact title and version. -->

## Checks

- [ ] `python3 scripts/build.py` and `python3 scripts/check_version.py BASE_SHA` pass
- [ ] A change under `schema/` bumps `VERSION`
- [ ] Values that aren't simply documented carry `verification`
- [ ] No em dash or en dash in the data, docs, commits or this text

## Hardware test

Complete this section when software acts on the data you changed. Otherwise write "Not
device-affecting" and say why.

- Head commit tested:
- Devices and firmware:
- Plan and result: <!-- link or paste the report -->
- State the devices were left in:

Mark the pull request ready only after this section is filled in.
