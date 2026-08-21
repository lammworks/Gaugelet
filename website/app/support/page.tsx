import type { Metadata } from "next";
import { documents } from "../content.generated";
import { MarkdownDocument } from "../components/MarkdownDocument";
import { SiteFooter, SiteHeader } from "../components/SiteChrome";

export const metadata: Metadata = {
  title: "Support",
  description: "Gaugelet setup help, troubleshooting, and issue-reporting guidance.",
  alternates: { canonical: "/support" },
};

export default function SupportPage() {
  return <><SiteHeader /><MarkdownDocument eyebrow="Help" source={documents["SUPPORT.md"]} /><SiteFooter /></>;
}
