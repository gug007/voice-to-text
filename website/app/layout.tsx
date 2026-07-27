import type { Metadata, Viewport } from "next";
import { Geist } from "next/font/google";
import Script from "next/script";

import { AnalyticsEvents } from "@/components/analytics-events";
import { IconSprite } from "@/components/icon-sprite";
import { AUTHOR_URL, GA_MEASUREMENT_ID, SITE_URL } from "@/lib/constants";
import { themeInitScript } from "@/lib/seo";

import "./globals.css";

const sans = Geist({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-sans",
});

const TITLE = "Free Voice-to-Text App for Mac — Offline & Open Source";
const DESCRIPTION =
  "Press Option+Space and dictate into any Mac app. VoiceToText is free and open source on Apple Silicon, with offline models and no required account.";
const TWITTER_DESCRIPTION =
  "Press Option+Space, speak, and type into any Mac app. Free and open source, with offline models and no required account.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  applicationName: "VoiceToText",
  authors: [{ name: "Gurgen Abagyan", url: AUTHOR_URL }],
  creator: "Gurgen Abagyan",
  publisher: "Gurgen Abagyan",
  category: "productivity",
  referrer: "origin-when-cross-origin",
  openGraph: {
    type: "website",
    siteName: "VoiceToText",
    url: SITE_URL,
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: TWITTER_DESCRIPTION,
  },
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/icon-64.png", sizes: "64x64", type: "image/png" },
      { url: "/app-icon.png", sizes: "512x512", type: "image/png" },
    ],
    apple: { url: "/app-icon.png", sizes: "512x512", type: "image/png" },
  },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0A0A0B" },
    { media: "(prefers-color-scheme: light)", color: "#FFFFFF" },
  ],
  colorScheme: "dark light",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={sans.variable} suppressHydrationWarning>
      <head>
        <link rel="dns-prefetch" href="https://github.com" />
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        {/* Keep content and the compact navigation usable before/without JavaScript. */}
        <noscript>
          <style>{`
            .reveal, .reveal-child { opacity: 1 !important; transform: none !important; }
            .theme-toggle { display: none !important; }
            @media (max-width: 960px) {
              .nav__primary, .nav__mobile, .nav__inner > .btn { display: none !important; }
              .nav__fallback { display: flex !important; }
            }
          `}</style>
        </noscript>
      </head>
      <body>
        <Script
          src={`https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`}
          strategy="afterInteractive"
        />
        <Script id="ga-init" strategy="afterInteractive">{`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', '${GA_MEASUREMENT_ID}');
        `}</Script>
        <AnalyticsEvents />

        <IconSprite />
        <a className="skip-link" href="#main">Skip to main content</a>
        {children}
      </body>
    </html>
  );
}
