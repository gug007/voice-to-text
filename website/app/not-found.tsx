import Link from "next/link";

import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { ScrollEffects } from "@/components/scroll-effects";
import { Icon } from "@/components/ui/icon";

// A segment not-found file can't export metadata, so the page names itself
// with React's hoisted <title>. Next still answers with a 404 status and adds
// <meta name="robots" content="noindex"> on its own.
export default function NotFound() {
  return (
    <>
      <title>Page not found · VoiceToText</title>
      <Nav linkPrefix="/" />
      <main id="main" tabIndex={-1}>
        <section className="section hero" aria-labelledby="nf-title">
          <div className="container hero__inner">
            <p className="hero__eyebrow">
              <span className="hero__eyebrow-dot" aria-hidden="true" />
              404
            </p>
            <h1 id="nf-title" className="hero__title">
              Page not found.
            </h1>
            <p className="hero__lead">
              The page you&rsquo;re looking for doesn&rsquo;t exist — but the free voice to text app for Mac
              is right here.
            </p>
            <div className="hero__ctas">
              <Link className="btn btn--primary btn--lg" href="/">
                <span>Go to the home page</span>
                <Icon name="arrow-right" />
              </Link>
              <Link className="btn btn--secondary btn--lg" href="/meeting-recording">
                <span>Record meetings on Mac</span>
              </Link>
            </div>
          </div>
        </section>
      </main>
      <Footer linkPrefix="/" />
      <ScrollEffects />
    </>
  );
}
