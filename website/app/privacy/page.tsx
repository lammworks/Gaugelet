import type { Metadata } from "next";
import { documents } from "../content.generated";
import { MarkdownDocument } from "../components/MarkdownDocument";
import { SiteFooter, SiteHeader } from "../components/SiteChrome";

export const metadata: Metadata = {
  title: "Privacy",
  description: "How Gaugelet handles Codex usage data and Sparkle update requests.",
  alternates: { canonical: "/privacy" },
};

export default function PrivacyPage() {
  return <><SiteHeader /><MarkdownDocument eyebrow="Policy" source={documents["PRIVACY.md"]} /><SiteFooter /></>;
}
