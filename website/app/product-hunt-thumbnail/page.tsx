/* eslint-disable @next/next/no-img-element -- deterministic fixed-size launch asset */
import type { Metadata } from "next";

export const metadata: Metadata = { title: "Gaugelet Product Hunt thumbnail", robots: { index: false, follow: false } };

export default function ProductHuntThumbnailPage() {
  return (
    <main className="asset-canvas thumbnail-card">
      <img className="thumbnail-orbit" src="/images/launch-orbit-background.png" alt="" />
      <img className="thumbnail-icon" src="/images/gaugelet-icon.png" alt="" />
      <strong>Gaugelet</strong>
    </main>
  );
}
