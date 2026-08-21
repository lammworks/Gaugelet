# Gaugelet release evidence template

- Release owner:
- Evidence reviewer:
- Version/build:
- Public source commit:
- GitHub Actions run:

## Owner-only local Sparkle finalization

Run from a clean checkout of the exact commit recorded in `build-evidence.txt`:

```zsh
Scripts/verify-sparkle-key-gates.sh --keychain-only
GAUGELET_SPARKLE_BACKUP_1=/absolute/offline-one/Gaugelet-Sparkle.age \
GAUGELET_SPARKLE_BACKUP_2=/absolute/offline-two/Gaugelet-Sparkle.age \
  Scripts/finalize-sparkle-release.sh /absolute/path/to/downloaded-release-assets
```

The backup files must be distinct age-encrypted, non-symlink files outside every Git work tree with mode `400` or `600`. These verification and finalization commands only look up the existing Keychain key; they never generate, export, decrypt, or print private material. Backup creation and recovery testing are separate owner-only procedures in [COMMUNITY_RELEASE_RUNBOOK.md](COMMUNITY_RELEASE_RUNBOOK.md).

## Sparkle custody record — no secrets

- Keychain owner: Diego
- Keychain service/account: `https://sparkle-project.org` / `Gaugelet`
- Public-key SHA-256 fingerprint:
- Backup A non-secret asset identifier / control domain / owner / creation date:
- Backup B non-secret asset identifier / control domain / owner / creation date:
- Passphrase custody record identifier and owner (never the passphrase):
- Recovery-drill backup asset identifier / date / operator / result:
- Recovery-drill public fingerprint matched: `YES / NO`
- Throwaway signature round trip passed: `YES / NO`
- Next recovery drill due:

Never place raw keys, passphrases, decrypted-file paths, backup download links, exact storage paths, or captured key-operation output in release evidence.

## Required local assets

- [ ] `Gaugelet.dmg`
- [ ] `Gaugelet.dmg.sha256`
- [ ] `Gaugelet.app.dSYM.zip`
- [ ] Signed `appcast.xml`
- [ ] `build-evidence.txt`
- [ ] `release-evidence.txt`
- [ ] `sparkle-evidence.txt`

## Build and integrity gates

- [ ] `Scripts/check.sh` passed on the source commit.
- [ ] The main executable is arm64-only.
- [ ] Sparkle is exactly 2.9.5 and its vendor universal helper binaries and framework symlinks are preserved.
- [ ] Nested Sparkle code and Gaugelet pass strict code-signature verification.
- [ ] The community build is ad-hoc signed without hardened runtime and is not described as Apple-verified.
- [ ] The app icon exposes transparency and the app has no `Icon\r`, FinderInfo, or resource-fork custom icon.
- [ ] `Gaugelet.dmg.sha256` verifies the exact downloaded DMG.
- [ ] Gatekeeper rejects the non-notarized community build as expected; the documented Open Anyway flow was tested.

## Sparkle gates

- [ ] `Scripts/verify-sparkle-key-gates.sh --keychain-only` confirms the committed `SUPublicEDKey` matches the dedicated maintainer Keychain account without printing the raw key.
- [ ] Two age-encrypted private-key backups exist outside every Git work tree, pass the non-secret metadata gate, and are documented in separate control domains.
- [ ] `Scripts/test-sparkle-key-recovery.sh` restored one backup into protected temporary storage; Keychain continuity matched and the throwaway signature round trip passed.
- [ ] `appcast.xml` was generated locally from the exact CI-built `Gaugelet.dmg`.
- [ ] The appcast uses `https://github.com/lammworks/Gaugelet/releases/download/vVERSION/Gaugelet.dmg`.
- [ ] Sparkle `sign_update` verifies the feed and full DMG EdDSA signatures.
- [ ] No delta files exist for 1.0.
- [ ] A seeded 1.0.0 to 1.0.1 update, tampered DMG, and tampered appcast were tested manually.

## Public repository settings and launch gates

- [ ] Mandatory built-in secret/PII and gitleaks scans passed; optional detect-secrets findings were also resolved when the tool was available.
- [ ] The public export hash manifest was created and verified.
- [ ] The public snapshot has one unrelated root commit and no private-development history.
- [ ] `main` requires PRs and CI; force pushes are blocked.
- [ ] `v*` tag deletion and force updates are blocked.
- [ ] Secret scanning and push protection are enabled.
- [ ] Private Vulnerability Reporting is enabled.
- [ ] Discussions are disabled.
- [ ] `.github/FUNDING.yml` is absent; no funding link is configured for 1.0.
- [ ] Public repository creation was separately approved.
- [ ] Public Sites deployment was separately approved.
- [ ] Draft GitHub Release assets were independently downloaded and reverified.
- [ ] Immutable GitHub Release publication was separately approved.
- [ ] Product Hunt submission was separately approved or remains unsubmitted.

- Decision: `BLOCKED / READY FOR OWNER APPROVAL / PUBLISHED`
- Residual risk accepted by:
- Evidence reviewer sign-off:
