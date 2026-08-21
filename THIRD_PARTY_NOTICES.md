# Third-party notices

This notice describes Gaugelet 1.0. `Package.resolved` and the contents of the distributed app bundle are the authoritative dependency inventory for a particular build.

## Sparkle 2.9.5

Gaugelet bundles [Sparkle 2.9.5](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.5) for update discovery, Ed25519 verification, download, and user-approved installation.

Sparkle is distributed under the [MIT License](https://github.com/sparkle-project/Sparkle/blob/2.9.5/LICENSE). Its copyright and license notice must remain in the vendor framework and release materials as supplied. Sparkle is a separate project and is not covered by Gaugelet's copyright notice.

Gaugelet pins Sparkle to version 2.9.5. A dependency update requires license, security, packaging, helper-signing, privacy, and update-path review before release.

## Codex CLI

Gaugelet requires the separately installed official Codex CLI for live usage. The Codex CLI is not bundled with Gaugelet and is not licensed under Gaugelet's MIT License. It is separate OpenAI software governed by OpenAI's applicable license, terms, and privacy notices.

Gaugelet starts `codex app-server` locally and requests `account/rateLimits/read`. Users obtain and authenticate Codex through official OpenAI channels.

## Apple platform components

Gaugelet uses Apple-provided macOS frameworks, system materials, and SF Symbols. Those components remain subject to Apple's licenses and usage guidelines.

## Contributor Covenant

Gaugelet's Code of Conduct is adapted from the [Contributor Covenant, version 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html), which is available under the [Creative Commons Attribution 4.0 License](https://creativecommons.org/licenses/by/4.0/).

## Names and brand assets

OpenAI, ChatGPT, Codex, and GPT are names or marks of OpenAI. Their use describes compatibility and does not imply affiliation, sponsorship, or endorsement.

Gaugelet source code is licensed under the repository's [MIT License](LICENSE). The Gaugelet name, icon, logo, and other brand assets are governed by [BRAND.md](BRAND.md), not the MIT License.

## Release review

Before each release, review `Package.swift`, `Package.resolved`, bundled frameworks and helpers, resources, generated notices, and the final app inventory. Confirm that every redistributed component permits distribution and that required license files survive packaging.

Built by LammWorks.
