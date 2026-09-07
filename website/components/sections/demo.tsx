import { TrafficLights } from "@/components/ui/traffic-lights";

export function Demo() {
  return (
    <section className="section demo" id="demo" aria-labelledby="demo-title">
      <div className="container">
        <div className="section__head section__head--center">
          <h2 id="demo-title" className="section__title">The real app, unedited.</h2>
          <p className="section__deck">
            Twenty seconds of VoiceToText dictating a prompt into a coding workspace on a Mac. No copy and
            paste, no window switching, nothing staged.
          </p>
        </div>
        <figure className="product-demo">
          <div className="product-demo__window">
            <div className="product-demo__chrome" aria-hidden="true">
              <TrafficLights />
              <span className="product-demo__chrome-title">Screen recording, no audio</span>
            </div>
            <video
              className="product-demo__video"
              controls
              muted
              loop
              playsInline
              preload="metadata"
              poster="/product-demo-poster.png"
              data-respect-reduced-motion
              data-analytics-event="demo_start"
              data-analytics-placement="home_demo"
              data-analytics-label="product_video"
              aria-label="Silent 20-second screen recording of VoiceToText dictating into a coding workspace"
            >
              <source src="/product-demo.mp4" type="video/mp4" />
              Your browser does not support embedded video. Use the setup guide below to see how VoiceToText works.
            </video>
          </div>
        </figure>
      </div>
    </section>
  );
}
