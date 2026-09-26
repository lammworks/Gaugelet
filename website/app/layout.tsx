import type { Metadata } from "next";
import "./globals.css";

// The canonical public origin. Override with SITE_URL when building for a
// preview host so the deployed origin is never hard-coded in the source.
const siteURL = new URL(
  process.env.SITE_URL ?? "https://gaugelet.lammworks.com",
);

export const metadata: Metadata = {
  metadataBase: siteURL,
  title: {
    default: "Gaugelet — Codex and ChatGPT allowance in your menu bar",
    template: "%s · Gaugelet",
  },
  description:
    "See the Codex and ChatGPT plan allowances returned through Codex from a private, Apple-silicon-native macOS menu-bar app.",
  applicationName: "Gaugelet",
  alternates: {
    canonical: "/",
  },
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/images/gaugelet-icon.png", type: "image/png", sizes: "1024x1024" },
    ],
    apple: [{ url: "/images/gaugelet-icon.png", sizes: "1024x1024" }],
  },
  openGraph: {
    type: "website",
    url: "/",
    siteName: "Gaugelet",
    title: "See your Codex and ChatGPT allowance before you hit the limit",
    description:
      "A beautiful, private, Apple-silicon-native menu-bar gauge with seven themes.",
    images: [
      {
        url: "/images/gaugelet-social.jpg",
        width: 1200,
        height: 630,
        alt: "Gaugelet showing Codex and ChatGPT allowance counters in the macOS menu bar",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "See your Codex and ChatGPT allowance before you hit the limit",
    description:
      "A beautiful, private, Apple-silicon-native menu-bar gauge with seven themes.",
    images: ["/images/gaugelet-social.jpg"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
