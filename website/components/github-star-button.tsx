import { ExternalLink } from "@/components/ui/external-link";
import { Glyph } from "@/components/ui/glyph";
import { REPO_URL } from "@/lib/constants";
import { formatStarCount, getStarCount } from "@/lib/github-stars";

/* A small count beside the logo reads as "few people use this", which the
 * download numbers don't support, so the count only shows once it helps. */
const SHOW_COUNT_FROM = 1000;

type GitHubStarButtonProps = {
  placement: string;
};

export async function GitHubStarButton({ placement }: GitHubStarButtonProps) {
  const stars = await getStarCount();
  const count = stars !== null && stars >= SHOW_COUNT_FROM ? formatStarCount(stars) : null;

  return (
    <ExternalLink
      className="star-btn"
      href={REPO_URL}
      data-analytics-event="github_outbound"
      data-analytics-placement={placement}
    >
      <span className="star-btn__label" data-nosnippet>
        <Glyph name="star" className="star-btn__icon" />
        Star
      </span>
      {/* The bar has no room for "on GitHub" at any width (measured: 54px past
          the grid), so it lives only in the accessible name. */}
      <span className="sr-only"> on GitHub</span>
      {count !== null && (
        <span className="star-btn__count" data-nosnippet>
          {count}
        </span>
      )}
    </ExternalLink>
  );
}
