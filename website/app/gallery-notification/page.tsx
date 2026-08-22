/* eslint-disable @next/next/no-img-element -- deterministic fixed-size launch asset */
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Gaugelet notification gallery",
  robots: { index: false, follow: false },
};

export default function GalleryNotificationPage() {
  return (
    <main className="asset-canvas feature-gallery notification-gallery-card">
      <header className="feature-gallery-header notification-gallery-header">
        <div className="feature-gallery-brand">
          <img src="/images/gaugelet-icon.png" alt="" />
          <span>Gaugelet</span>
        </div>
        <span>Private by design · Alerts stay on your Mac</span>
      </header>

      <section className="feature-gallery-copy notification-gallery-copy">
        <p>Native notifications</p>
        <h1>Get the warning before the work stops.</h1>
        <small>
          Pick your threshold. Gaugelet alerts only when a live allowance crosses it,
          so you still have time to lower the model, reasoning, or pace.
        </small>
        <div className="notification-proof-list">
          <span><i>01</i> Live readings only</span>
          <span><i>02</i> Your threshold</span>
          <span><i>03</i> No analytics</span>
        </div>
      </section>

      <section className="notification-gallery-stage" aria-label="Gaugelet low allowance notification preview">
        <div className="notification-menu-chip">
          <img src="/images/gaugelet-menubar.svg" alt="" />
          <strong>18%</strong>
        </div>

        <div className="native-alert-card">
          <img src="/images/gaugelet-icon.png" alt="" />
          <div>
            <p><strong>Gaugelet</strong><span>now</span></p>
            <h2>Weekly allowance is low · 18% left</h2>
          </div>
        </div>

        <div className="notification-app-window">
          <div className="gallery-window-traffic" aria-hidden="true"><i /><i /><i /></div>
          <div className="gallery-window-header">
            <div>
              <img src="/images/gaugelet-icon.png" alt="" />
              <span><strong>Gaugelet</strong><small>ChatGPT plan usage</small></span>
            </div>
            <b>LIVE</b>
          </div>
          <div className="notification-window-body">
            <p>Most constrained returned limit</p>
            <article>
              <div><span>General usage</span><strong>Weekly usage limit</strong></div>
              <b>18%<small>left</small></b>
              <div className="notification-meter"><i /></div>
              <small>◷ &nbsp; Resets in 3d 7h</small>
            </article>
          </div>
        </div>

        <div className="threshold-control-card">
          <div><span>Alert me at</span><strong>20% remaining</strong></div>
          <div className="threshold-track"><i /><b /></div>
          <small>100%</small><small>0%</small>
        </div>
      </section>

      <footer className="feature-gallery-footer notification-gallery-footer">
        <span>Five-minute refresh</span><span>Manual refresh</span><span>OpenAI limits remain authoritative</span>
      </footer>
    </main>
  );
}
