import type { Metadata } from "next";
import { BrandMark, SiteFooter, SiteHeader } from "./components/SiteChrome";

export const metadata: Metadata = {
  title: "See your Codex and ChatGPT allowance before you hit the limit",
  description:
    "Gaugelet is a private, native macOS menu-bar gauge for the Codex and ChatGPT plan allowances returned through Codex on your Mac.",
};

const limits = [
  { label: "5-hour", remaining: 74, reset: "Resets in 2h 18m" },
  { label: "Weekly", remaining: 42, reset: "Resets Monday" },
  { label: "Codex Spark", remaining: 88, reset: "Weekly window" },
];

const adjustments = [
  { number: "01", title: "Model", copy: "Choose the capability the task actually needs." },
  { number: "02", title: "Reasoning", copy: "Spend depth where it creates a better result." },
  { number: "03", title: "Pace", copy: "Slow the burn before a hard stop ends the run." },
];

const themes = [
  { name: "Core", slug: "core" },
  { name: "Dark Dracula", slug: "dracula" },
  { name: "Ember", slug: "ember" },
  { name: "Moss", slug: "moss" },
  { name: "Mono", slug: "mono" },
  { name: "8-Bit", slug: "eight-bit" },
  { name: "Pride", slug: "pride" },
];

const coffeeURL = "https://www.paypal.com/donate/?hosted_button_id=Z4QV6SJVXSCH4";

export default function Home() {
  return (
    <main>
      <SiteHeader />

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">
            <span className="status-dot" aria-hidden="true" />
            Gaugelet 1.0 · macOS 14+
          </p>
          <h1>Know what is left.<br />Keep the work moving.</h1>
          <p className="lede">
            A native menu-bar gauge for the Codex and ChatGPT allowance exposed
            through Codex on your Mac—so you can tune the model, reasoning, and
            pace before a hard limit stops the job.
          </p>
          <div className="hero-actions">
            <a
              className="button button-primary"
              href="https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg"
            >
              Download Gaugelet 1.0
              <span aria-hidden="true">↓</span>
            </a>
            <a className="button button-secondary" href="/install">
              Read install guide
            </a>
          </div>
          <p className="hero-note">
            Free and MIT licensed · Native for Apple silicon · Private by default · Five-minute refresh
          </p>
        </div>

        <div className="app-stage" aria-label="Gaugelet app preview">
          <div className="menu-bar-chip">
            <span className="mini-gauge" aria-hidden="true" />
            <span>42%</span>
          </div>
          <div className="app-window">
            <div className="window-topline">
              <div className="window-brand">
                <BrandMark compact />
                <div>
                  <strong>Gaugelet</strong>
                  <small>Codex + ChatGPT allowance</small>
                </div>
              </div>
              <span className="live-pill">LIVE</span>
            </div>

            <div className="limit-stack">
              {limits.map((limit) => (
                <article className="limit-card" key={limit.label}>
                  <div className="limit-heading">
                    <span>{limit.label}</span>
                    <strong>{limit.remaining}% <small>left</small></strong>
                  </div>
                  <div className="meter" aria-hidden="true">
                    <span style={{ width: `${limit.remaining}%` }} />
                  </div>
                  <p>{limit.reset}</p>
                </article>
              ))}
            </div>

            <div className="window-footer">
              <span>Updated just now</span>
              <span aria-hidden="true">↻</span>
            </div>
          </div>
          <p className="truth-note">
            <span aria-hidden="true">i</span>
            OpenAI’s enforced limits remain authoritative.
          </p>
        </div>
      </section>

      <section className="signal-section section-shell">
        <div className="section-heading">
          <p className="section-kicker">Your plan, at a glance</p>
          <h2>The familiar counters, without breaking your flow.</h2>
          <p>
            Gaugelet keeps the overall, weekly, and special-model windows for your
            ChatGPT plan in stable positions when Codex returns them. Missing windows
            stay unavailable; any additional windows appear below them.
          </p>
        </div>
        <div className="counter-grid" aria-label="Example allowance counters">
          {limits.map((limit, index) => (
            <article key={limit.label}>
              <div className="counter-topline">
                <span>0{index + 1}</span>
                <strong>{limit.remaining}%</strong>
              </div>
              <h3>{limit.label}</h3>
              <p>{limit.reset}</p>
              <div className="meter"><span style={{ width: `${limit.remaining}%` }} /></div>
            </article>
          ))}
        </div>
        <p className="section-footnote">Example values only. Your available windows come from Codex on your Mac.</p>
      </section>

      <section className="mac-section section-shell" id="made-for-mac">
        <div className="mac-showcase">
          <div className="mac-intro">
            <div>
              <p className="section-kicker">Made for the Mac</p>
              <h2>Useful enough to keep open. Beautiful enough to belong.</h2>
            </div>
            <p>
              Gaugelet is a focused macOS utility—not a web dashboard squeezed into
              a desktop window. It is built for Apple silicon, lives in the menu bar,
              follows your Mac’s appearance, and stays out of the way until you need it.
            </p>
          </div>

          <div className="mac-feature-grid">
            <article className="mac-feature-card theme-feature">
              <div className="feature-copy">
                <span className="feature-index">01 · Make it yours</span>
                <h3>Seven themes. One glanceable gauge.</h3>
                <p>
                  Choose a look that fits your desktop—from quiet Core and Mono to
                  Dark Dracula, 8-Bit, and Pride. The menu-bar icon and in-app accents
                  update together while the signed system icon stays consistently Gaugelet.
                </p>
              </div>
              <div className="theme-rack" aria-label="Gaugelet themes">
                {themes.map((theme) => (
                  <div className="theme-token" key={theme.slug}>
                    <span className={`theme-gauge theme-${theme.slug}`} aria-hidden="true">
                      <i />
                    </span>
                    <strong>{theme.name}</strong>
                  </div>
                ))}
              </div>
            </article>

            <article className="mac-feature-card silicon-feature">
              <div className="silicon-chip" aria-hidden="true">
                <span>arm64</span>
                <i></i>
              </div>
              <div className="feature-copy">
                <span className="feature-index">02 · Native by design</span>
                <h3>Made for Apple silicon.</h3>
                <p>
                  A native arm64 app for macOS 14 and newer, with launch at login,
                  light and dark appearance support, and optional native notifications.
                </p>
              </div>
            </article>

            <article className="mac-feature-card local-feature">
              <div className="local-path" aria-label="Local-first data path">
                <span>Codex</span><i aria-hidden="true">→</i><span>Your Mac</span>
              </div>
              <div className="feature-copy">
                <span className="feature-index">03 · Local-first privacy</span>
                <h3>Your allowance is not our business.</h3>
                <p>
                  No Gaugelet account, analytics, telemetry, usage-history upload,
                  or LammWorks backend. Gaugelet reads the local Codex App Server and
                  displays the result on your Mac.
                </p>
              </div>
            </article>
          </div>

          <div className="mac-proof-row" aria-label="Native Mac features">
            <span>macOS 14+</span>
            <span>Apple silicon</span>
            <span>Light + dark</span>
            <span>Launch at login</span>
            <span>Native notifications</span>
          </div>
        </div>
      </section>

      <section className="adjust-section">
        <div className="section-shell adjust-grid">
          <div className="adjust-copy">
            <p className="section-kicker light">A gauge for real decisions</p>
            <h2>Use the plan you already paid for—deliberately.</h2>
            <p>
              When the remaining allowance is visible, small choices stay small. You can
              lower capability or pace and keep moving instead of discovering the limit
              only when the work stops.
            </p>
          </div>
          <div className="adjust-list">
            {adjustments.map((item) => (
              <article key={item.title}>
                <span>{item.number}</span>
                <div><h3>{item.title}</h3><p>{item.copy}</p></div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="source-section section-shell">
        <div className="section-heading compact-heading">
          <p className="section-kicker">Honest by design</p>
          <h2>Local readings. Clear limits.</h2>
          <p>
            Gaugelet asks the local Codex App Server for the same rate-limit windows Codex
            exposes on your Mac. It refreshes every five minutes, or whenever you ask.
          </p>
        </div>
        <div className="data-path" aria-label="How Gaugelet reads usage">
          <div><span>1</span><strong>Codex App Server</strong><small>Local source</small></div>
          <i aria-hidden="true">→</i>
          <div><span>2</span><strong>Gaugelet</strong><small>No account or backend</small></div>
          <i aria-hidden="true">→</i>
          <div><span>3</span><strong>Menu bar</strong><small>Five-minute view</small></div>
        </div>
        <aside className="accuracy-card">
          <strong>Why the numbers can differ</strong>
          <p>
            The local Codex reading and ChatGPT’s UI are separate views and can drift—sometimes
            materially during heavy use. Gaugelet can move faster or slower. OpenAI’s enforced
            limit is always the authority.
          </p>
        </aside>
      </section>

      <section className="privacy-strip">
        <div className="section-shell privacy-grid">
          <div>
            <p className="section-kicker">Private by default</p>
            <h2>Your usage stays on your Mac.</h2>
          </div>
          <div>
            <p>
              No Gaugelet account, analytics, telemetry, backend, or usage-history upload.
              Sparkle contacts GitHub only to check the signed update feed.
            </p>
            <a href="/privacy">Read the privacy policy <span aria-hidden="true">→</span></a>
          </div>
        </div>
      </section>

      <section className="maker-section section-shell" id="support-the-project">
        <div className="maker-card">
          <div className="maker-copy">
            <p className="section-kicker light">Independent, on purpose</p>
            <h2>One developer. One useful little Mac app.</h2>
            <p>
              I’m Diego, the independent developer behind Gaugelet. The app is free
              and open source. If it earns a permanent place in your menu bar, a coffee
              helps fund the unglamorous work: testing new macOS releases, keeping
              updates healthy, and polishing the details.
            </p>
            <div className="maker-signature">
              <span aria-hidden="true">D</span>
              <div><strong>Diego · LammWorks</strong><small>Independent maker in Panama</small></div>
            </div>
          </div>

          <aside className="coffee-card">
            <div className="coffee-cup" aria-hidden="true"><span /></div>
            <p>Like Gaugelet?</p>
            <h3>Buy me a coffee.</h3>
            <p>Optional, appreciated, and never tied to features.</p>
            <a
              className="button coffee-button"
              href={coffeeURL}
              target="_blank"
              rel="noreferrer"
            >
              Buy me a coffee <span aria-hidden="true">↗</span>
            </a>
            <a className="maker-source-link" href="https://github.com/lammworks/Gaugelet">
              Or contribute on GitHub <span aria-hidden="true">→</span>
            </a>
          </aside>
        </div>
      </section>

      <section className="final-cta section-shell">
        <BrandMark />
        <p className="section-kicker">Gaugelet 1.0</p>
        <h2>See the limit before it becomes the problem.</h2>
        <p>Free, open source, private by default, and built for Apple-silicon Macs running macOS 14 or later.</p>
        <div className="hero-actions">
          <a className="button button-primary" href="https://github.com/lammworks/Gaugelet/releases/download/v1.0.0/Gaugelet.dmg">
            Download Gaugelet 1.0 <span aria-hidden="true">↓</span>
          </a>
          <a className="button button-secondary" href="https://github.com/lammworks/Gaugelet">View source</a>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
