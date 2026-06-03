import { ScrollEffects } from "@/components/scroll-effects";
import { Cloud } from "@/components/sections/cloud";
import { Compare } from "@/components/sections/compare";
import { Demo } from "@/components/sections/demo";
import { Download } from "@/components/sections/download";
import { Faq } from "@/components/sections/faq";
import { Features } from "@/components/sections/features";
import { Footer } from "@/components/sections/footer";
import { Hero } from "@/components/sections/hero";
import { HowItWorks } from "@/components/sections/how-it-works";
import { Nav } from "@/components/sections/nav";
import { Proof } from "@/components/sections/proof";
import { Realtime } from "@/components/sections/realtime";
import { UseCases } from "@/components/sections/use-cases";
import { StickyCta } from "@/components/sticky-cta";

export default function Home() {
  return (
    <>
      <Nav />
      <main id="main" tabIndex={-1}>
        <Hero />
        <Proof />
        <Demo />
        <HowItWorks />
        <Features />
        <Cloud />
        <Realtime />
        <UseCases />
        <Compare />
        <Faq />
        <Download />
      </main>
      <Footer />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
