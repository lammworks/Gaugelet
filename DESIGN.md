# Gaugelet design direction

Gaugelet is a compact, native macOS utility for checking the usage windows returned for a user's ChatGPT plan and identifying the one most likely to block the next task.

The interaction and information hierarchy are inspired by ChatGPT's restrained, task-first product UI: native typography, quiet surfaces, one dominant answer, consistent “remaining” language, and semantic state colors. The product identity is intentionally independent:

- Petrol blue is the everyday accent.
- Warm copper marks low remaining allowance.
- Coral is reserved for a reached limit.
- The app uses an original name and an SF Symbols gauge, not OpenAI's Blossom.
- “ChatGPT” and “Codex” appear only as descriptive product references.

The public product name is **Gaugelet**. `GPTBar` remains only the existing repository name.

This design direction is not legal or trademark clearance. Distribution materials should retain the non-affiliation statement and receive normal name/trademark review before a public launch.

## Usage language and hierarchy

The primary surface uses the language a ChatGPT subscriber already sees:

- `ChatGPT plan usage`
- `General usage`
- `Weekly usage limit`
- `5 hour usage limit`
- `24% left`
- `Resets in 29m`

Provider names, model names, protocol state, and experimental-source detail are secondary or settings-level information. The dashboard itself is fixed-height and does not scroll in normal use. The prominent card shows the most constrained returned window; the bounded **Other returned limits** surface retains the other counters, with a five-minute refresh note so users can make deliberate model and reasoning trade-offs.

## Icon family

Core, Dark Dracula (Aurora), Ember, Moss, Monochrome, 8-Bit, and Pride share identical gauge geometry and differ primarily in palette. 8-Bit preserves the same silhouette and gauge reading as an intentional pixel-art treatment. They are appearance choices, not unrelated logos.

- The selected variant appears inside Gaugelet's header and About/Settings surfaces and drives the app's adaptive accent palette; a selected icon produces matching controls, progress, selection, links, and glass tint rather than Core teal.
- Warning, critical, error, destructive, and demo colors remain semantic and do not change with the appearance choice.
- Ember uses the icon's gold highlight rather than its copper body color so a healthy Ember state remains visibly distinct from the fixed copper warning state.
- 8-Bit uses deliberately large pixel clusters so the treatment remains visible in the larger selector controls.
- All styles are free at launch.
- The shipping system source is a full-bleed, opaque, unmasked Core square compiled through the AppIcon asset catalog. macOS owns the final mask and edge treatment for Finder, the notification permission sheet, and delivered notifications.
- Theme variants are limited to Gaugelet's menu-bar and in-app surfaces. They never write a custom Finder icon into the installed app bundle, which keeps the signed application immutable after installation.
- A future Icon Composer file may add genuine layered dark/mono behavior, but it is not required for the 1.0 community release.

## Installation experience

The DMG is a product surface. Its 720×440 Finder window uses reviewed 1×/2× artwork, a single explicit instruction, quiet icon wells, a left-to-right drag arrow, 128-point icons, fixed positions, and light label wells that maintain readable Finder-owned dark item labels. Pinned `dmgbuild` settings write the layout headlessly; release verification reads `.DS_Store`, background metadata, and label-zone luminance rather than trusting a screenshot alone.

## Liquid Glass

Gaugelet treats Liquid Glass as a system material, not a static translucent color:

- The shipping `NSPopover` owns the outer glass surface so macOS can adapt blur, tint, contrast, and vibrancy to the desktop beneath it.
- On macOS 26 and newer, the standard popover adopts Liquid Glass automatically when linked with the current SDK.
- Older supported macOS releases retain their native semantic popover material rather than receiving a visual imitation.
- Usage cards and settings groups remain quieter standard materials inside the content layer; nested Liquid Glass would reduce hierarchy and legibility.
- The selected icon's accessible accent stays confined to identity, progress, and interactive states; warm copper and coral retain their semantic meanings.
- Reduce Transparency, Increase Contrast, appearance, and motion preferences remain system-controlled.

This follows Apple's guidance to reserve Liquid Glass for the functional layer and use standard materials within content. See [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
