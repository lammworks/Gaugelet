# Gaugelet community release runbook

This is the active release path for Gaugelet 1.0: free, MIT-licensed, native for Apple silicon, ad-hoc code-signed, and not Apple-notarized. Sparkle authenticates updates after installation; it does not remove the initial Gatekeeper **Open Anyway** requirement.

The release owner must keep a dated evidence folder. A passing build is a candidate until every gate below is closed for the same bytes.

## 1. Authority and stop points

Assign a release owner, builder, QA owner, and second reviewer. One person may hold multiple roles, but the final artifact and evidence need an independent review.

Stop for explicit approval before:

- Creating or making public `lammworks/Gaugelet`.
- Creating a public GitHub Release or uploading assets.
- Publishing the immutable release.
- Deploying Sites publicly or changing the repository homepage.
- Submitting Product Hunt or posting launch advertising.

Do not delete private branches, archive the private repository, rewrite history, or remove the private provenance repository as part of release work.

## 2. Preflight

Confirm:

- The release branch has passing CI and is merged to private `main`.
- `CFBundleShortVersionString` is the intended semantic version.
- `CFBundleVersion` is a new, monotonically increasing integer.
- The public snapshot contains only allowlisted source and documentation.
- Sparkle is pinned exactly to 2.9.5 in `Package.swift` and `Package.resolved`.
- The app's main executable is built for arm64; Sparkle's vendor-supplied internals are not unsafely thinned.
- The stable blue Core icon is used for Finder, permission prompts, and notifications.
- Current README, install, privacy, support, security, notices, and changelog copy matches the community distribution model.
- The release host, support intake, and GitHub Private Vulnerability Reporting work.

For 1.0.0, verify:

```text
CFBundleShortVersionString = 1.0.0
CFBundleVersion = 1
tag = v1.0.0
```

## 3. Create and verify the clean public snapshot

After approval to create the public repository:

1. Export an allowlisted snapshot of final private `main` into a new directory.
2. Exclude private Git history, `QA/`, old Dipstick material, internal monetization/readiness research, generated builds, local caches, and unsanitized screenshots.
3. Generate a file-hash manifest from the allowlist and compare it with the exported tree.
4. Scan the export for secrets, credentials, tokens, private keys, email addresses, usernames, absolute home paths, and other PII. Review findings manually; do not treat a tool's zero count as sufficient evidence.
5. Initialize an unrelated repository with one root commit using the approved GitHub noreply identity.
6. Build only from that public commit. Record its SHA in release evidence.

Configure `main` PR/CI protection, protected `v*` tags, SHA-pinned Actions with read-only default permissions, Dependabot, secret scanning, push protection, issue forms, PR template, and Private Vulnerability Reporting before publication. Keep Discussions disabled.

## 4. Sparkle key-custody gate

The production Ed25519 key is created once with Sparkle 2.9.5's vendor `generate_keys` utility. Its operational private copy stays in Diego's login Keychain under service `https://sparkle-project.org` and account `Gaugelet`. Do not run `generate_keys` without an explicit lookup, import, or export flag: its default mode creates a key when none exists.

Required custody controls:

- Embed and commit only `SUPublicEDKey`. Never commit or upload a private-key export, an encrypted backup, its passphrase, or recovery material.
- Keep two age-encrypted backups in separate control domains, not merely two folders on the same Mac, storage device, provider account, or GitHub account.
- Keep the age passphrase in a password manager or recovery record controlled separately from both backup files.
- Restore-test one backup in a disposable macOS user, prove that its public key matches the embedded key, and sign and verify a throwaway file.
- Record only the public-key fingerprint, creation dates, non-secret asset identifiers, owners, restore-test result, and next test date in protected evidence. Do not record raw keys, passphrases, decrypted-file paths, or terminal output from key operations.

### Read-only checks

These commands do not generate, export, decrypt, or print private material. They report only pass/fail status and a SHA-256 fingerprint of the public key:

```bash
Scripts/verify-sparkle-key-gates.sh --configuration-only
Scripts/verify-sparkle-key-gates.sh --keychain-only
```

The second command fails unless the existing `Gaugelet` Keychain item produces the same public key as committed `SUPublicEDKey`. To validate the two already-created encrypted containers without decrypting them:

```bash
GAUGELET_SPARKLE_BACKUP_1=/absolute/location-one/Gaugelet-Sparkle-Key.age \
GAUGELET_SPARKLE_BACKUP_2=/absolute/location-two/Gaugelet-Sparkle-Key.age \
  Scripts/verify-sparkle-key-gates.sh
```

That verifier checks paths, age headers, file permissions, Git-work-tree exclusion, hard links, distinct file identity, and Keychain/public-key continuity. It cannot prove independent administrative control or recoverability; those remain manual evidence gates.

### One-time backup creation — owner action only

If two backups already exist, do not recreate or rotate them. Otherwise, after installing [`age`](https://age-encryption.org/), Diego must run the following locally and interactively, outside any recorded or shared terminal session:

```bash
Scripts/backup-sparkle-key.sh \
  /absolute/independent-location-one/Gaugelet-Sparkle-Key.age \
  /absolute/independent-location-two/Gaugelet-Sparkle-Key.age
```

This is the sole planned export event. The script asks Sparkle to place a transient plaintext export in a private mode-`700` temporary directory, encrypts it immediately, installs two mode-`600` encrypted copies without overwriting existing files, and removes the transient plaintext on every handled exit path. The primary private key remains in Keychain. Do not run this operation through CI, screen sharing, shell tracing, an assistant, or a captured terminal. Never paste the passphrase into a command, issue, pull request, release log, or conversation.

### One-time recovery drill — owner action only

Run the owner-only drill against one encrypted backup in a private Terminal window:

```bash
Scripts/test-sparkle-key-recovery.sh \
  /absolute/independent-location-one/Gaugelet-Sparkle-Key.age
```

The drill first confirms that the production Keychain item matches committed `SUPublicEDKey`. It then prompts locally for the age passphrase, decrypts the selected backup only inside a private mode-`700` temporary directory, signs a throwaway probe with the recovered file, and verifies that signature against the Keychain key trusted by Gaugelet. The script never imports or replaces a Keychain item, never prints private material, never uses a release artifact, and removes the temporary plaintext automatically on every handled exit path.

This cryptographic round trip is the required 1.0 recovery gate. A disposable-user Keychain import drill is an optional annual defense-in-depth exercise if the maintainer wants to test the full machine-migration procedure. Record only date, operator, backup asset identifier, matching public fingerprint, pass/fail result, and next annual drill date.

If `--keychain-only` fails, stop and do not run bare `generate_keys`. First locate the original Keychain or an existing encrypted recovery copy for the embedded public-key fingerprint. If any release using that public key has shipped, treat an unrecoverable key as an update-channel incident and do not replace `SUPublicEDKey` silently. If no release has ever shipped and the original key is genuinely unrecoverable, Diego must make an explicit pre-release decision to create one new production key, embed its public half, and restart all custody gates. If either encrypted backup is missing or restoration has not been tested, the release remains blocked. Losing this key can strand installed clients.

## 5. Verify Sparkle configuration

Inspect the packaged `Info.plist`, not only the source plist. Require:

```text
SUFeedURL = https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml
SUPublicEDKey = <approved Gaugelet public key>
SURequireSignedFeed = true
SUVerifyUpdateBeforeExtraction = true
SUEnableSystemProfiling = false
SUAutomaticallyUpdate = false
SUAllowsAutomaticUpdates = false
```

The normal interval is 24 hours after the user accepts automatic checks. Silent download and installation are disabled. For the 1.0 channel, generate full-DMG enclosures only; do not publish delta updates.

Fail the release if the public key is empty, a placeholder, different from the custody record, or if the feed URL points anywhere except the canonical GitHub release channel.

## 6. Build and attest in GitHub Actions

From the tagged public commit, run the protected community-release workflow. The workflow must use SHA-pinned actions and read-only permissions unless a narrower documented permission is required for attestation.

The workflow must:

- Resolve the pinned Swift package.
- Build Gaugelet's executable for arm64.
- Preserve Sparkle framework symlinks and vendor helper architectures.
- Embed Sparkle under `Gaugelet.app/Contents/Frameworks` with bundle-relative runtime paths.
- Sign nested Sparkle helpers and framework inside-out, then sign Gaugelet ad-hoc.
- Avoid hardened runtime for the community build if library validation prevents the supported Sparkle runtime.
- Run tests and package verification.
- Create `Gaugelet.dmg`, `Gaugelet.dmg.sha256`, the dSYM archive, and release/build evidence.
- Generate a GitHub artifact attestation tied to the public commit and workflow run.

Run locally from a clean checkout as well:

```bash
./Scripts/bootstrap-dmg-tools.sh
swift package resolve
swift test
./Scripts/check.sh
```

Record the selected toolchain, SDK, runner image, package resolution, workflow URL/run ID, commit SHA, test output, and artifact attestation.

## 7. Packaging verification

On the CI-produced artifact, verify:

- `Gaugelet.app/Contents/MacOS/Gaugelet` is arm64.
- Sparkle remains in `Contents/Frameworks` with required symlinks intact.
- Runtime load paths are bundle-relative and resolve inside the app.
- Sparkle helpers/framework and the app pass strict nested signature verification.
- No custom Finder `Icon\r`, custom-icon Finder flag, or runtime-mutated bundle icon exists.
- The compiled Core `AppIcon.icns` contains transparency and consistent visual sizing.
- The DMG contains Gaugelet plus an `/Applications` link and passes layout verification.
- The dSYM UUID matches the arm64 executable.
- `Gaugelet.dmg.sha256` verifies the DMG.

Use strict code-signature validation:

```bash
codesign --verify --deep --strict --verbose=4 Gaugelet.app
shasum -a 256 -c Gaugelet.dmg.sha256
hdiutil verify Gaugelet.dmg
```

An ad-hoc signature proves internal code integrity, not publisher identity. Record Gatekeeper rejection as expected:

```bash
spctl --assess --type execute --verbose=4 Gaugelet.app
```

Do not convert that expected rejection into a pass or describe the artifact as Apple-verified.

## 8. Generate and authenticate the appcast locally

Download the attested CI artifact to the release owner's Mac and verify its digest before signing update metadata. Do not rebuild or alter the DMG locally.

Using Sparkle 2.9.5's vendor tooling and the Keychain-held private key:

1. Generate the Ed25519 enclosure signature for `Gaugelet.dmg`.
2. Generate `appcast.xml` with no delta enclosure.
3. Confirm the enclosure length equals the final DMG byte length.
4. Confirm the enclosure URL is version-specific:

   `https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg`

5. Confirm feed discovery remains stable:

   `https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml`

6. Validate the feed signature and enclosure signature with the public key embedded in the packaged app.
7. Add the signed `appcast.xml` and its validation output to release evidence.

Never print, export to an unencrypted file, upload, or paste the private key into a terminal transcript, CI secret, issue, pull request, release note, or GitHub setting.

## 9. Prepare the draft release

After explicit approval to create the public release, create a draft for protected tag `v1.0.0`. Attach exactly:

- `Gaugelet.dmg`
- `Gaugelet.dmg.sha256`
- `appcast.xml`
- The versioned dSYM archive
- Release/build evidence
- Attestation references or downloadable attestation material

Release notes must state Apple-silicon/macOS 14+ support, Codex CLI requirement, five-minute refresh, possible drift, OpenAI authority, ad-hoc signing, non-notarized status, Open Anyway steps, Sparkle update behavior, privacy links, and non-affiliation.

Do not publish yet. Asset names and version-specific URLs become part of the update contract.

## 10. Test the exact uploaded bytes

Download every asset back from the draft release using the approved authenticated path. Recompute hashes and compare the downloaded DMG byte-for-byte with the CI artifact.

On a clean macOS test profile or clean supported Mac:

- Install to `/Applications` from the downloaded DMG.
- Confirm Gatekeeper blocks first launch, then complete **Privacy & Security → Open Anyway**.
- Confirm no Full Disk Access or other broad privacy permission is requested.
- Confirm Finder, notification permission, and delivered notifications use the blue Core icon with transparent corners.
- Test live, stale, unavailable, demo, blocked, and signed-out states.
- Verify canonical counter positions, unavailable missing windows, additional returned windows, five-minute refresh, and manual refresh.
- Confirm values are presented as informational and can drift from ChatGPT.
- Test Launch at Login through logout/login and after returning from System Settings.
- Accept and reject Sparkle automatic-check consent; test manual check, offline behavior, and a missing-feed response.
- Use a private seeded feed to complete a `1.0.0 → 1.0.1` replacement test.
- Confirm Launch at Login intent and preferences survive replacement.
- Confirm a tampered appcast and tampered update DMG are rejected.

Test on the current stable macOS release. If launch occurs after macOS 27 ships, add macOS 27 acceptance evidence.

Any failure invalidates the candidate until fixed and re-run from the public commit.

## 11. Publish immutably

Before publication, confirm GitHub immutable releases are enabled and that tag deletion and force-push are blocked.

Obtain explicit approval to publish. Then publish the draft without changing assets. Record the publication time and release URL.

Immediately download from the public URLs, repeat SHA-256 and appcast retrieval checks, and confirm:

- `https://github.com/lammworks/Gaugelet/releases/latest/download/appcast.xml` resolves to the published feed.
- The version-specific enclosure resolves to the DMG whose digest and length are recorded.
- The repository README download CTA resolves to the same bytes.

If post-publication bytes or routes differ, stop promotion. Do not edit assets in place.

## 12. Closeout and rollback readiness

Retain the public commit, tag, workflow logs, attestations, package resolution, exact artifacts, hashes, appcast, signature validation, toolchain details, clean-machine results, approvals, and key-custody record in protected evidence storage.

For a functional or privacy defect:

1. Stop promotion and mark the affected version clearly.
2. Preserve the immutable artifact and evidence.
3. Determine affected users and whether they should stop using the app.
4. Fix forward with a higher version and build.
5. Repeat this complete runbook.

For a signing-key or release-channel incident, follow [SECURITY.md](SECURITY.md). Do not publish a new feed until installed clients have a verified recovery path.

Built by LammWorks.
