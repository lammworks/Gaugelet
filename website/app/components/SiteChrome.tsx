import Link from "next/link";

export function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={`brand-mark${compact ? " compact" : ""}`} aria-hidden="true">
      <span />
    </span>
  );
}

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link className="brand" href="/" aria-label="Gaugelet home">
        <BrandMark />
        <span>Gaugelet</span>
      </Link>
      <nav aria-label="Primary navigation">
        <Link href="/install">Install</Link>
        <Link href="/support">Support</Link>
        <a href="https://github.com/lammworks/Gaugelet">GitHub</a>
      </nav>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div>
        <Link className="brand footer-brand" href="/" aria-label="Gaugelet home">
          <BrandMark compact />
          <span>Gaugelet</span>
        </Link>
        <p>Built by LammWorks.</p>
      </div>
      <nav aria-label="Footer navigation">
        <Link href="/privacy">Privacy</Link>
        <Link href="/security">Security</Link>
        <Link href="/support">Support</Link>
        <Link href="/changelog">Changelog</Link>
        <a href="https://github.com/lammworks/Gaugelet">Source</a>
      </nav>
      <p className="footer-note">Unofficial. Not affiliated with OpenAI.</p>
    </footer>
  );
}
