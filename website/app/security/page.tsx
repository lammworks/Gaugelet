import type { Metadata } from "next";
import { documents } from "../content.generated";
import { MarkdownDocument } from "../components/MarkdownDocument";
import { SiteFooter, SiteHeader } from "../components/SiteChrome";

export const metadata: Metadata = {
  title: "Security",
  description: "Gaugelet’s security model and private vulnerability-reporting process.",
  alternates: { canonical: "/security" },
};

export default function SecurityPage() {
  return <><SiteHeader /><MarkdownDocument eyebrow="Security" source={documents["SECURITY.md"]} /><SiteFooter /></>;
}
