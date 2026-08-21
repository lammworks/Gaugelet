/* eslint-disable @next/next/no-img-element -- deterministic fixed-size launch asset */
import type { Metadata } from "next";

export const metadata: Metadata = { title: "Gaugelet decision story", robots: { index: false, follow: false } };

const decisions = [
  ["01", "Model", "Match capability to the task."],
  ["02", "Reasoning", "Spend depth where it matters."],
  ["03", "Pace", "Slow the burn before the stop."],
];

export default function GalleryDecisionsPage() {
  return (
    <main className="asset-canvas decision-card">
      <header><img src="/images/gaugelet-icon.png" alt="" /><span>Gaugelet 1.0</span></header>
      <div className="decision-copy">
        <p>A gauge for real decisions</p>
        <h1>Adjust before the limit decides for you.</h1>
        <small>See what is left, then choose how the next task should run.</small>
      </div>
      <div className="decision-options">
        {decisions.map(([number, title, copy]) => (
          <article key={title}><span>{number}</span><h2>{title}</h2><p>{copy}</p></article>
        ))}
      </div>
      <footer>Five-minute refresh · Manual refresh · OpenAI limits are authoritative</footer>
    </main>
  );
}
