import { REPO_URL } from "@/lib/constants";

export type LatestRelease = {
  /** Git tag, e.g. "v0.0.57". */
  tag: string;
  /** Tag without the leading "v", e.g. "0.0.57". */
  version: string;
  /** ISO date (YYYY-MM-DD) the release was published. */
  publishedAt: string;
  /** The release page on GitHub. */
  url: string;
};

type GitHubRelease = {
  tag_name?: string;
  published_at?: string | null;
  html_url?: string;
  draft?: boolean;
  prerelease?: boolean;
};

const LATEST_RELEASE_API_URL = `${REPO_URL.replace("https://github.com/", "https://api.github.com/repos/")}/releases/latest`;

const REVALIDATE_SECONDS = 60 * 60 * 24;

/** Snapshot served when the GitHub API is unreachable or rate-limited at build time. */
export const FALLBACK_RELEASE: LatestRelease = {
  tag: "v0.0.57",
  version: "0.0.57",
  publishedAt: "2026-09-22",
  url: `${REPO_URL}/releases/tag/v0.0.57`,
};

function toRelease(raw: GitHubRelease): LatestRelease | null {
  if (raw.draft || raw.prerelease || !raw.tag_name || !raw.published_at || !raw.html_url) return null;
  const publishedAt = raw.published_at.slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(publishedAt)) return null;
  return {
    tag: raw.tag_name,
    version: raw.tag_name.replace(/^v/, ""),
    publishedAt,
    url: raw.html_url,
  };
}

export async function getLatestRelease(): Promise<LatestRelease> {
  try {
    const headers: Record<string, string> = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

    const res = await fetch(LATEST_RELEASE_API_URL, { headers, next: { revalidate: REVALIDATE_SECONDS } });
    if (!res.ok) return FALLBACK_RELEASE;

    const data: unknown = await res.json();
    if (!data || typeof data !== "object") return FALLBACK_RELEASE;

    return toRelease(data as GitHubRelease) ?? FALLBACK_RELEASE;
  } catch {
    return FALLBACK_RELEASE;
  }
}
