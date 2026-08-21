# Gaugelet release runbook

This file routes release work. The detailed procedures are:

- [COMMUNITY_RELEASE_RUNBOOK.md](COMMUNITY_RELEASE_RUNBOOK.md) — current free community channel: ad-hoc code signing, no Apple notarization, Sparkle-authenticated updates.
- [NOTARIZED_RELEASE_RUNBOOK.md](NOTARIZED_RELEASE_RUNBOOK.md) — dormant future channel requiring an active Apple Developer membership, Developer ID, hardened runtime, and notarization.

Gaugelet 1.0 uses the **community** path. Never mix claims or evidence between the two paths.

## Release contract

Every release must:

- Come from an identified commit in the clean public `lammworks/Gaugelet` repository.
- Use semantic app versions and a monotonically increasing integer bundle build.
- Pass CI and the local release checks from a clean checkout.
- Preserve Sparkle 2.9.5's framework structure and validate its nested signatures.
- Produce `Gaugelet.dmg`, `Gaugelet.dmg.sha256`, signed `appcast.xml`, a dSYM archive, and release/build evidence.
- Use a version-specific Sparkle enclosure URL and the stable latest-release appcast URL.
- Test the exact downloaded bytes, not a nearby local build.
- Publish immutable releases; never replace an asset while retaining its version, URL, or digest.
- Record who approved, built, verified, and published the release.

## Approval checkpoints

Stop and obtain explicit approval immediately before each outbound action:

1. Creating or making public the `lammworks/Gaugelet` repository.
2. Creating the public GitHub Release or uploading release assets.
3. Publishing the immutable GitHub Release.
4. Deploying the Sites project publicly or changing the repository homepage.
5. Submitting Gaugelet to Product Hunt or posting launch advertising.

A local build, private preview, draft copy, or prepared upload list is not approval for the next checkpoint.

## Release decision

| Condition | Decision |
| --- | --- |
| Community gates pass, Gatekeeper rejection is recorded as expected, Sparkle verification passes | Candidate may proceed to approved publication |
| Artifact is described as Apple-verified or notarized without evidence | Stop |
| Sparkle key has fewer than two tested encrypted backups | Stop |
| Public export contains secrets, PII, private history, excluded QA, or internal research | Stop |
| CI artifact and locally tested artifact do not have the same SHA-256 digest | Stop |
| Any asset changes after final digest or Sparkle signature generation | Rebuild and repeat all downstream gates |
| A vulnerability, privacy discrepancy, compromised link, or update-authentication failure is open | Stop and follow incident response |

## Version policy

Gaugelet 1.0.0 uses:

- `CFBundleShortVersionString = 1.0.0`
- `CFBundleVersion = 1`
- Git tag `v1.0.0`

Future releases increment the integer bundle build. User-visible compatibility changes follow semantic versioning. Never reuse a version or build for different bytes.

## Common rollback rule

Do not silently replace an immutable release. Stop promotion, preserve evidence, explain the affected version, and fix forward with a new version and higher build after completing the entire applicable runbook.

Built by LammWorks.
