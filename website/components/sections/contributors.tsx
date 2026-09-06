import Image from "next/image";

import { ISSUES_URL, REPO_URL } from "@/lib/constants";
import { getContributors } from "@/lib/contributors";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";

function commitLabel(count: number) {
  return count === 1 ? "1 commit" : `${count.toLocaleString("en-US")} commits`;
}

export async function Contributors() {
  const contributors = await getContributors();

  return (
    <section className="section contributors" id="contributors" aria-labelledby="contributors-title">
      <div className="container contributors__inner">
        <div className="contributors__intro">
          <h2 id="contributors-title" className="section__title">
            Built in public, by these people.
          </h2>
          <p className="section__deck">
            Every commit, issue, and release happens in the open on GitHub. These are the contributors
            who have shipped code to the project so far. Pull requests are welcome.
          </p>
          <div className="contributors__ctas">
            <ExternalLink
              className="btn btn--secondary"
              href={REPO_URL}
              data-analytics-event="github_outbound"
              data-analytics-placement="contributors"
            >
              <Icon name="github" />
              <span>Contribute on GitHub</span>
            </ExternalLink>
            <ExternalLink className="contributors__issues" href={ISSUES_URL}>
              Report an issue
            </ExternalLink>
          </div>
        </div>
        <ul className="contributors__list" role="list">
          {contributors.map(({ login, url, avatarUrl, contributions }) => (
            <li key={login}>
              <ExternalLink className="contributor" href={url}>
                <Image className="contributor__avatar" src={avatarUrl} width={44} height={44} alt="" />
                <span className="contributor__body">
                  <span className="contributor__name">@{login}</span>
                  <span className="contributor__meta">{commitLabel(contributions)}</span>
                </span>
              </ExternalLink>
            </li>
          ))}
          <li>
            <ExternalLink className="contributor contributor--invite" href={REPO_URL}>
              <span className="contributor__avatar contributor__avatar--placeholder" aria-hidden="true">
                +
              </span>
              <span className="contributor__body">
                <span className="contributor__name">You?</span>
                <span className="contributor__meta">Open a pull request</span>
              </span>
            </ExternalLink>
          </li>
        </ul>
      </div>
    </section>
  );
}
