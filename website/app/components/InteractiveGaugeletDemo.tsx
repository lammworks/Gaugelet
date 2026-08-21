"use client";

/* eslint-disable @next/next/no-img-element -- The fixed local product icon must preserve its exact transparent pixels. */

import { useEffect, useRef, useState, type CSSProperties } from "react";

type Theme = {
  name: string;
  slug: string;
  accent: string;
  accentSoft: string;
  panel: string;
  card: string;
  ink: string;
  muted: string;
  track: string;
  stage: string;
};

const themes: Theme[] = [
  {
    name: "Core",
    slug: "core",
    accent: "#3977d5",
    accentSoft: "#d9e8fb",
    panel: "#f7f8fb",
    card: "#ffffff",
    ink: "#172033",
    muted: "#697486",
    track: "#e3e8ef",
    stage: "#173e70",
  },
  {
    name: "Dracula",
    slug: "dracula",
    accent: "#bd93f9",
    accentSoft: "#443d5e",
    panel: "#282a36",
    card: "#343746",
    ink: "#f8f8f2",
    muted: "#b7b8c4",
    track: "#4a4d5c",
    stage: "#173a69",
  },
  {
    name: "Ember",
    slug: "ember",
    accent: "#ef984d",
    accentSoft: "#4d3528",
    panel: "#2e251f",
    card: "#3a2e27",
    ink: "#fff7ef",
    muted: "#cbb9a9",
    track: "#57463a",
    stage: "#6c3a27",
  },
  {
    name: "Moss",
    slug: "moss",
    accent: "#65c4a4",
    accentSoft: "#d9f0e8",
    panel: "#f3f8f5",
    card: "#ffffff",
    ink: "#173128",
    muted: "#647a71",
    track: "#dce8e2",
    stage: "#245a4c",
  },
  {
    name: "Mono",
    slug: "mono",
    accent: "#818793",
    accentSoft: "#e7e8eb",
    panel: "#f5f5f5",
    card: "#ffffff",
    ink: "#25272b",
    muted: "#73767d",
    track: "#e1e2e5",
    stage: "#424750",
  },
  {
    name: "8-Bit",
    slug: "eight-bit",
    accent: "#4bc6f1",
    accentSoft: "#193f53",
    panel: "#0d2a3e",
    card: "#15364c",
    ink: "#eafaff",
    muted: "#9fc6d4",
    track: "#285267",
    stage: "#164d70",
  },
  {
    name: "Pride",
    slug: "pride",
    accent: "#df5ca6",
    accentSoft: "#4b3450",
    panel: "#282232",
    card: "#373041",
    ink: "#fff6fd",
    muted: "#c9b5c7",
    track: "#51465a",
    stage: "#5a3566",
  },
];

const fixedLimits = [
  { label: "5 hour usage limit", remaining: 68, reset: "Resets in 2h 13m" },
  { label: "Weekly usage limit", remaining: 88, reset: "Codex Spark · Resets in 5d 2h" },
];

type DemoStyle = CSSProperties & Record<`--demo-${string}`, string>;

export function InteractiveGaugeletDemo() {
  const [themeSlug, setThemeSlug] = useState("dracula");
  const [allowance, setAllowance] = useState(18);
  const [threshold, setThreshold] = useState(20);
  const [isSimulating, setIsSimulating] = useState(false);
  const timers = useRef<number[]>([]);
  const theme = themes.find((item) => item.slug === themeSlug) ?? themes[0];
  const isLow = allowance <= threshold;

  const style: DemoStyle = {
    "--demo-accent": theme.accent,
    "--demo-accent-soft": theme.accentSoft,
    "--demo-panel": theme.panel,
    "--demo-card": theme.card,
    "--demo-ink": theme.ink,
    "--demo-muted": theme.muted,
    "--demo-track": theme.track,
    "--demo-stage": theme.stage,
  };

  const clearTimers = () => {
    timers.current.forEach((timer) => window.clearTimeout(timer));
    timers.current = [];
  };

  useEffect(() => clearTimers, []);

  const simulateHeavySession = () => {
    clearTimers();
    setIsSimulating(true);
    setAllowance(42);
    [36, 29, 23, 18].forEach((nextValue, index, values) => {
      const timer = window.setTimeout(() => {
        setAllowance(nextValue);
        if (index === values.length - 1) setIsSimulating(false);
      }, 320 * (index + 1));
      timers.current.push(timer);
    });
  };

  const resetDemo = () => {
    clearTimers();
    setThemeSlug("core");
    setAllowance(42);
    setThreshold(20);
    setIsSimulating(false);
  };

  return (
    <div className="product-demo" style={style}>
      <div className="demo-stage">
        <div
          className={`native-notification${isLow ? " is-visible" : ""}`}
          role="status"
          aria-live="polite"
        >
          <img src="/images/gaugelet-icon.png" alt="" />
          <div>
            <div className="notification-topline">
              <strong>Gaugelet</strong>
              <span>now</span>
            </div>
            <p>Weekly allowance is low · {allowance}% left</p>
          </div>
        </div>

        <div className="demo-menu-chip" aria-label={`${allowance}% allowance left`}>
          <img src="/images/gaugelet-icon.png" alt="" />
          <strong>{allowance}%</strong>
        </div>

        <div className="demo-window-wrap">
          <div className={`demo-app-window theme-${theme.slug}`}>
            <div className="mac-window-bar" aria-hidden="true">
              <span className="traffic-light traffic-red" />
              <span className="traffic-light traffic-yellow" />
              <span className="traffic-light traffic-green" />
            </div>

            <div className="demo-app-header">
              <div className="demo-app-brand">
                <img src="/images/gaugelet-icon.png" alt="" />
                <div>
                  <strong>Gaugelet</strong>
                  <small>ChatGPT plan usage</small>
                </div>
              </div>
              <span className="demo-pill">DEMO</span>
              <button className="settings-button" type="button" aria-label="Demo settings">
                <span aria-hidden="true">•••</span>
              </button>
            </div>

            <div className="demo-app-content">
              <div className="usage-heading">
                <div>
                  <span>ChatGPT plan usage</span>
                  <strong>ChatGPT plan</strong>
                </div>
                <button type="button" aria-label="Refresh demo usage" onClick={() => setAllowance((value) => value)}>
                  <span aria-hidden="true">↻</span>
                </button>
              </div>

              <p className="limit-group-label">Most constrained returned limit</p>
              <article className={`primary-limit-card${isLow ? " is-low" : ""}`}>
                <div className="primary-limit-topline">
                  <div>
                    <small>General usage</small>
                    <strong>Weekly usage limit</strong>
                  </div>
                  <div className="primary-value">
                    <strong>{allowance}%</strong>
                    <small>left</small>
                  </div>
                </div>
                <div className="demo-meter" aria-label={`${allowance}% weekly allowance left`}>
                  <span style={{ width: `${allowance}%` }} />
                </div>
                <p>◷ &nbsp; Resets in 3d 7h</p>
              </article>

              <p className="limit-group-label other-limits-label">Other returned limits</p>
              <div className="other-limit-card">
                {fixedLimits.map((limit) => (
                  <div className="compact-limit" key={limit.label}>
                    <div>
                      <strong>{limit.label}</strong>
                      <span>{limit.remaining}% left</span>
                    </div>
                    <small>{limit.reset}</small>
                    <div className="demo-meter"><span style={{ width: `${limit.remaining}%` }} /></div>
                  </div>
                ))}
              </div>

              <p className="demo-data-note">Demo data — not your account</p>
              <div className="demo-app-footer">
                <span>Updated 15 sec</span>
                <span>5 min refresh</span>
                <span>Read-only</span>
                <strong>Open ChatGPT</strong>
              </div>
            </div>
          </div>
        </div>

        <div className="demo-controls" aria-label="Try Gaugelet controls">
          <div className="theme-control">
            <div className="control-label-row">
              <span>Theme</span>
              <strong>{theme.name}</strong>
            </div>
            <div className="theme-buttons">
              {themes.map((item) => (
                <button
                  key={item.slug}
                  className={themeSlug === item.slug ? "is-selected" : ""}
                  type="button"
                  aria-label={`Use ${item.name} theme`}
                  aria-pressed={themeSlug === item.slug}
                  onClick={() => setThemeSlug(item.slug)}
                  style={{ "--swatch": item.accent } as CSSProperties}
                >
                  <span />
                  <small>{item.name}</small>
                </button>
              ))}
            </div>
          </div>

          <div className="allowance-control">
            <span>
              <span>Allowance</span>
              <strong>{allowance}%</strong>
            </span>
            <input
              type="range"
              aria-label="Remaining allowance"
              min="1"
              max="100"
              value={allowance}
              onChange={(event) => {
                clearTimers();
                setIsSimulating(false);
                setAllowance(Number(event.target.value));
              }}
            />
          </div>

          <label className="alert-control">
            <span>Alert at</span>
            <select value={threshold} onChange={(event) => setThreshold(Number(event.target.value))}>
              <option value="10">10%</option>
              <option value="20">20%</option>
              <option value="30">30%</option>
            </select>
          </label>
        </div>
        <div className="demo-action-buttons">
          <button type="button" className="simulate-button" onClick={simulateHeavySession} disabled={isSimulating}>
            {isSimulating ? "Running session…" : "Simulate heavy session"}
          </button>
          <button type="button" className="reset-button" onClick={resetDemo}>Reset</button>
        </div>
        <p className="demo-invitation">Switch themes. Burn the allowance. See the warning before your work stops.</p>
      </div>
    </div>
  );
}
