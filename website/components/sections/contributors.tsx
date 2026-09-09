import Image from "next/image";
import type { CSSProperties } from "react";

import { ISSUES_URL, REPO_URL } from "@/lib/constants";
import { getContributors } from "@/lib/contributors";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";

type HueStyle = CSSProperties & Record<"--h", string>;

const CHIP_ITEM: CSSProperties = { display: "flex" };
const CHIP: CSSProperties = { textDecoration: "none", flex: "1 1 auto", minWidth: 0 };
const CHIP_BODY: CSSProperties = { display: "grid", gap: "1px", minWidth: 0 };
const CHIP_META: CSSProperties = { fontSize: "13px", lineHeight: 1.35 };
const AVATAR: CSSProperties = { width: "26px", height: "26px", borderRadius: "8px", flex: "none" };
const INVITE_HUE: HueStyle = { "--h": "258" };
const CTAS: CSSProperties = { display: "flex", flexWrap: "wrap", alignItems: "center", gap: "12px 18px", marginTop: "24px" };

function commitLabel(count: number) {
  return count === 1 ? "1 commit" : `${count.toLocaleString("en-US")} commits`;
}

export async function Contributors() {
  const contributors = await getContributors();

  return (
    <section className="section" id="contributors" aria-labelledby="contributors-title">
      <div className="wrap">
        <div className="sec-head">
          <p className="kicker">Aside &middot; who builds it</p>
          <h2 id="contributors-title">Built in public, by these people.</h2>
          <p className="lede">
            Every commit, issue, and release happens in the open on GitHub. These are the contributors
            who have shipped code to the project so far.
          </p>
        </div>

        <ul className="apps" role="list">
          {contributors.map(({ login, url, avatarUrl, contributions }) => (
            <li key={login} style={CHIP_ITEM}>
              <ExternalLink className="app" href={url} style={CHIP}>
                <Image style={AVATAR} src={avatarUrl} width={26} height={26} alt="" />
                <span style={CHIP_BODY}>
                  <span>@{login}</span>
                  <span className="muted" style={CHIP_META}>{commitLabel(contributions)}</span>
                </span>
              </ExternalLink>
            </li>
          ))}
          <li style={CHIP_ITEM}>
            <ExternalLink className="app" href={REPO_URL} style={CHIP}>
              <span className="app__i" style={INVITE_HUE} aria-hidden="true">+</span>
              <span style={CHIP_BODY}>
                <span>You?</span>
                <span className="muted" style={CHIP_META}>Open a pull request</span>
              </span>
            </ExternalLink>
          </li>
        </ul>

        <p className="apps__foot">
          <b>Pull requests are welcome.</b> The repo, the issues, and every release live on GitHub.
        </p>

        <div style={CTAS}>
          <ExternalLink
            className="btn btn--ghost"
            href={REPO_URL}
            data-analytics-event="github_outbound"
            data-analytics-placement="contributors"
          >
            <Icon name="github" />
            <span>Contribute on GitHub</span>
          </ExternalLink>
          <ExternalLink className="link" href={ISSUES_URL}>
            Report an issue
          </ExternalLink>
        </div>
      </div>
    </section>
  );
}
