import type { Metadata } from "next";
import { documents } from "../content.generated";
import { MarkdownDocument } from "../components/MarkdownDocument";
import { SiteFooter, SiteHeader } from "../components/SiteChrome";

export const metadata: Metadata = {
  title: "Install",
  description: "Install the Developer ID signed and Apple-notarized Gaugelet app on an Apple-silicon Mac.",
  alternates: { canonical: "/install" },
};

export default function InstallPage() {
  return <><SiteHeader /><MarkdownDocument eyebrow="Installation guide" source={documents["INSTALL.md"]} /><SiteFooter /></>;
}
