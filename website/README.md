# Gaugelet launch site

This directory contains the Gaugelet landing site and the exact-size launch assets used for repository and Product Hunt preparation.

## Local development

Use Node.js 22.13 or newer.

```bash
npm ci
npm run dev
npm test
```

`npm run sync:content` copies the canonical repository Markdown into a generated TypeScript module. The `/install`, `/privacy`, `/support`, `/security`, and `/changelog` routes render that generated content. `npm test` fails if the generated module drifts from the root documents.

## Launch assets

The social and Product Hunt assets under `public/images/` are deterministic browser captures of the hidden asset routes:

- `/social-card` → `gaugelet-social.jpg` at 1200×630.
- `/product-hunt-thumbnail` → `product-hunt-thumbnail.jpg` at 240×240.
- `/` → `product-hunt-gallery-1.jpg` at 1270×760.
- `/gallery-decisions` → `product-hunt-gallery-2.jpg` at 1270×760.
- `/gallery-themes` → `product-hunt-gallery-3-themes.jpg` at 1270×760.
- `/gallery-notification` → `product-hunt-gallery-4-notification.jpg` at 1270×760.

`gaugelet-dashboard.png` is a native window capture from the exact verified candidate DMG, launched with Gaugelet's clearly labeled three-counter demo and Core theme.

`npm run check:assets` validates their formats, dimensions, and thumbnail size limit.

The source stays in the public Gaugelet repository. A private Sites preview is deployed first; public deployment remains an explicit approval checkpoint.
