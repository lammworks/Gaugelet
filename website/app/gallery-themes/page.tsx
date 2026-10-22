/* eslint-disable @next/next/no-img-element -- deterministic fixed-size launch asset */
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Gaugelet theme gallery",
  robots: { index: false, follow: false },
};

const themes = [
  ["Core", "core"],
  ["Dracula", "dracula"],
  ["Ember", "ember"],
  ["Moss", "moss"],
  ["Mono", "mono"],
  ["8-Bit", "eight-bit"],
  ["Pride", "pride"],
];

export default function GalleryThemesPage() {
  return (
    <main className="asset-canvas feature-gallery theme-gallery-card">
      <header className="feature-gallery-header">
        <div className="feature-gallery-brand">
          <img src="/images/gaugelet-icon.png" alt="" />
          <span>Gaugelet</span>
        </div>
        <span>Native for Apple silicon · macOS 14+</span>
      </header>

      <section className="feature-gallery-copy">
        <p>Seven in-app themes</p>
        <h1>Make the gauge feel at home.</h1>
        <small>
          Choose the palette that fits your desktop. Gaugelet’s window, accents,
          and in-app icon move together—without sacrificing clarity.
        </small>
        <div className="feature-gallery-proof">
          <strong>One clean menu-bar gauge.</strong>
          <span><img src="/images/gaugelet-menubar.svg" alt="" /> 42%</span>
        </div>
      </section>

      <section className="theme-gallery-stage" aria-label="Gaugelet theme selection preview">
        <div className="theme-window-shadow" aria-hidden="true" />
        <div className="theme-gallery-window">
          <div className="gallery-window-traffic" aria-hidden="true">
            <i /><i /><i />
          </div>
          <div className="gallery-window-header">
            <div>
              <img src="/images/gaugelet-icon.png" alt="" />
              <span><strong>Gaugelet</strong><small>ChatGPT plan usage</small></span>
            </div>
            <b>DRACULA</b>
          </div>
          <div className="gallery-window-body">
            <p>Most constrained returned limit</p>
            <article>
              <div><span>General usage</span><strong>Weekly usage limit</strong></div>
              <b>42%<small>left</small></b>
              <div className="gallery-theme-meter"><i /></div>
              <small>◷ &nbsp; Resets in 3d 7h</small>
            </article>
            <div className="gallery-mini-limits">
              <span><strong>5 hour usage limit</strong><b>68% left</b></span>
              <span><strong>Codex Spark</strong><b>88% left</b></span>
            </div>
          </div>
        </div>

        <div className="theme-picker-card">
          <p>Choose your look</p>
          <div className="theme-picker-row">
            {themes.map(([name, slug]) => (
              <div className={`gallery-theme-option gallery-theme-${slug}`} key={slug}>
                <span aria-hidden="true"><i /></span>
                <strong>{name}</strong>
              </div>
            ))}
          </div>
        </div>
      </section>

      <footer className="feature-gallery-footer">
        <span>Core</span><span>Dracula</span><span>Ember</span><span>Moss</span>
        <span>Mono</span><span>8-Bit</span><span>Pride</span>
      </footer>
    </main>
  );
}
