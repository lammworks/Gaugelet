import type { Metadata } from "next";
import { documents } from "../content.generated";
import { MarkdownDocument } from "../components/MarkdownDocument";
import { SiteFooter, SiteHeader } from "../components/SiteChrome";

export const metadata: Metadata = {
  title: "Changelog",
  description: "What changed in Gaugelet releases.",
  alternates: { canonical: "/changelog" },
};

export default function ChangelogPage() {
  return <><SiteHeader /><MarkdownDocument eyebrow="Release history" source={documents["CHANGELOG.md"]} /><SiteFooter /></>;
}
