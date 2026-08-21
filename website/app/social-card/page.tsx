/* eslint-disable @next/next/no-img-element -- deterministic fixed-size launch asset */
import type { Metadata } from "next";

export const metadata: Metadata = { title: "Gaugelet social card", robots: { index: false, follow: false } };

export default function SocialCardPage() {
  return (
    <main className="asset-canvas social-card">
      <img className="asset-backdrop" src="/images/launch-orbit-background.png" alt="" />
      <div className="asset-copy">
        <div className="asset-brand">
          <img src="/images/gaugelet-icon.png" alt="" />
          <span>Gaugelet</span>
        </div>
        <p>Native for Apple silicon · macOS 14+</p>
        <h1>See your Codex + ChatGPT allowance before you hit the limit.</h1>
        <div className="asset-footer">
          <span>Seven themes · Open source · Private by default</span>
          <strong>1.0</strong>
        </div>
      </div>
    </main>
  );
}
