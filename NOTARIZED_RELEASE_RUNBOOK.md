# Gaugelet Developer ID and notarized release runbook

Status: **Dormant.** Do not use or advertise this path until LammWorks has an active Apple Developer membership, a controlled Developer ID Application identity, notarization credentials, and a passing end-to-end test.

This path is for a future release after the community channel. It does not change the ad-hoc, non-notarized status of Gaugelet 1.0.

## 1. Activation decision

Activate this workflow only after an explicit strategy and budget approval. Record:

- Apple Developer account owner and renewal owner.
- Developer ID Application certificate owner, Team ID, expiry, and revocation path.
- Protected signing machine or CI environment.
- App Store Connect API/notarization credential owner and rotation plan.
- Whether hardened runtime and library validation are compatible with the pinned Sparkle release.
- Supported macOS versions and architecture claim.
- Migration plan for existing community-channel users.

Do not publish a notarized build under a version or build number already used for different community bytes. Fix forward with a new semantic version and higher integer build.

## 2. Preserve Sparkle trust continuity

Developer ID signing and Sparkle signing solve different problems. Keep the existing Gaugelet Sparkle Ed25519 key unless a separately tested key-rotation plan is approved.

- The private Sparkle key remains in the release owner's macOS Keychain with two encrypted, independently stored, restore-tested backups.
- Only `SUPublicEDKey` is embedded in the app.
- The feed remains `https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml` unless a versioned migration is shipped first.
- Continue signed-feed and pre-extraction verification.
- Continue user confirmation for download and installation unless a later product decision, privacy update, and QA plan explicitly change it.

A valid Developer ID signature does not permit unsigned Sparkle metadata, and a valid Sparkle signature does not replace notarization.

## 3. Provision credentials

Use a controlled macOS Keychain. Do not place certificates, `.p12` files, API `.p8` files, passwords, or exported Sparkle private keys in the repository, workflow logs, release evidence, or ordinary cloud storage.

Verify the intended identity before building:

```bash
security find-identity -v -p codesigning
```

The selected identity must be a valid `Developer ID Application` identity for the approved Team ID. Store notarization credentials with `xcrun notarytool store-credentials` in the protected Keychain or use narrowly scoped protected CI secrets. Record the credential identifier and owner, never the secret value.

Configure certificate-expiry and Apple-membership renewal reminders before the first public notarized release.

## 4. Update the dormant automation

Before execution, review `Scripts/release.sh` and the notarized GitHub Actions workflow against the current app version, arm64 packaging, Sparkle 2.9.5 layout, asset names, and release outputs.

The workflow must fail closed unless all required credentials and version confirmations are present. It must not publish a GitHub Release automatically.

Required build order:

1. Resolve the pinned Swift package.
2. Build Gaugelet for arm64.
3. Embed Sparkle under `Contents/Frameworks`, preserving vendor symlinks and helper architecture support.
4. Apply only reviewed entitlements.
5. Sign Sparkle helpers, XPC services, updater apps, and framework inside-out with secure timestamps and hardened runtime where required.
6. Sign Gaugelet last with Developer ID Application, hardened runtime, secure timestamp, and the approved Team ID.
7. Build and sign the DMG without changing the signed app bytes.
8. Submit the final DMG to Apple's notarization service.
9. Require an `Accepted` result, retain the submission ID and complete log, then staple and validate the DMG.

If hardened runtime or library validation breaks Sparkle, stop. Resolve the supported signing/entitlement configuration with the pinned framework and retest; do not disable security controls silently in the notarized channel.

## 5. Build and notarize

Use protected environment variables or equivalent secret references, not literal credentials:

```bash
export GAUGELET_SIGNING_IDENTITY='Developer ID Application: verified name (TEAMID)'
export GAUGELET_SIGNING_KEYCHAIN='/path/to/protected.keychain-db'
export GAUGELET_NOTARY_PROFILE='GaugeletNotary'
./Scripts/release.sh
```

The script or workflow must record the public identity, Team ID, certificate expiry, commit SHA, app version/build, toolchain, SDK, package resolution, and notarization submission ID. It must not record passwords, private keys, or credential bodies.

Generate the SHA-256 digest only after all signing, notarization, and stapling steps are complete. Any changed byte invalidates downstream evidence.

## 6. Verification gates

Verify the packaged app, mounted DMG app, and DMG as applicable:

```bash
codesign --verify --deep --strict --verbose=4 Gaugelet.app
codesign --display --verbose=4 Gaugelet.app
hdiutil verify Gaugelet.dmg
xcrun stapler validate Gaugelet.dmg
spctl --assess --type execute --verbose=4 Gaugelet.app
spctl --assess --type open --context context:primary-signature --verbose=4 Gaugelet.dmg
```

Evidence must prove:

- Approved Developer ID authority and Team ID.
- Secure timestamp and hardened runtime on the app.
- Strict nested signature validity for Sparkle components.
- Bundle-relative Sparkle runtime paths and preserved framework symlinks.
- arm64 Gaugelet executable and matching dSYM UUID.
- `Accepted` notarization result and valid staple.
- Passing Gatekeeper assessment without Open Anyway.
- Transparent Core app icon and no Finder custom-icon artifacts.
- Final DMG digest and byte size.

Do not infer any item from a neighboring build.

## 7. Update and replacement testing

On clean supported Macs, test both paths:

1. Fresh quarantined download and first launch without a Gatekeeper bypass.
2. Sparkle replacement of the previous community release with the new Developer ID/notarized release.

Confirm the Sparkle feed and enclosure signatures, update consent, offline and invalid-feed behavior, Launch at Login survival, preferences, notification permission, live-data states, and rollback behavior. Test tampered appcast and enclosure rejection.

The release notes must clearly say which version begins Developer ID/notarized distribution. Do not imply that older community builds became notarized retroactively.

## 8. Publication and closeout

Public repository, release upload, immutable publication, public Sites changes, and launch promotion each require explicit approval as described in [RELEASE_RUNBOOK.md](RELEASE_RUNBOOK.md).

Create a draft release, upload the final DMG, checksum, signed appcast, dSYM archive, notarization record, and release evidence, then download and test the exact draft bytes. After approval, publish immutably and repeat public-download verification.

Retain certificate, notarization, Gatekeeper, Sparkle, clean-machine, and approval evidence. Schedule certificate expiry, Apple membership renewal, dependency review, backup restoration, and release-channel access checks.

## 9. Incident response

If a certificate, notarization credential, Sparkle key, or release channel may be compromised, stop distribution, preserve evidence, restrict credentials, contact Apple Developer Support when applicable, and publish recovery instructions through a verified unaffected channel.

Never replace an immutable asset. Release remediation with a new version and build after the chain of trust is re-established.

Built by LammWorks.
