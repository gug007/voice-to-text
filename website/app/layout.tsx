import type { Metadata, Viewport } from "next";
import Script from "next/script";

import { AnalyticsEvents } from "@/components/analytics-events";
import { IconSprite } from "@/components/icon-sprite";
import { AUTHOR_URL, GA_MEASUREMENT_ID, SITE_URL } from "@/lib/constants";
import {
  HOME_DESCRIPTION,
  HOME_TITLE,
  HOME_TWITTER_DESCRIPTION,
  themeInitScript,
} from "@/lib/seo";

import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: HOME_TITLE,
  description: HOME_DESCRIPTION,
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
    title: HOME_TITLE,
    description: HOME_DESCRIPTION,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: HOME_TITLE,
    description: HOME_TWITTER_DESCRIPTION,
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
    { media: "(prefers-color-scheme: dark)", color: "#1E1E20" },
    { media: "(prefers-color-scheme: light)", color: "#F4F4F7" },
  ],
  colorScheme: "light dark",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="dns-prefetch" href="https://github.com" />
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        {/* Keep content and the compact navigation usable before/without JavaScript. */}
        <noscript>
          <style>{`
            .reveal, .reveal-child { opacity: 1 !important; transform: none !important; }
            .theme-toggle { display: none !important; }
            @media (max-width: 1040px) {
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
