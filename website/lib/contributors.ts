import { REPO_URL } from "@/lib/constants";

export type Contributor = {
  login: string;
  url: string;
  avatarUrl: string;
  contributions: number;
};

type GitHubContributor = {
  login?: string;
  html_url?: string;
  avatar_url?: string;
  contributions?: number;
  type?: string;
};

const CONTRIBUTORS_API_URL = `${REPO_URL.replace("https://github.com/", "https://api.github.com/repos/")}/contributors?per_page=100`;

const REVALIDATE_SECONDS = 60 * 60 * 24;

/** Snapshot served when the GitHub API is unreachable or rate-limited at build time. */
export const FALLBACK_CONTRIBUTORS: Contributor[] = [
  {
    login: "gug007",
    url: "https://github.com/gug007",
    avatarUrl: "https://avatars.githubusercontent.com/u/9885501?v=4",
    contributions: 164,
  },
  {
    login: "jesse-merhi",
    url: "https://github.com/jesse-merhi",
    avatarUrl: "https://avatars.githubusercontent.com/u/79823012?v=4",
    contributions: 27,
  },
  {
    login: "Jesse-Dur",
    url: "https://github.com/Jesse-Dur",
    avatarUrl: "https://avatars.githubusercontent.com/u/104001848?v=4",
    contributions: 1,
  },
];

function toContributor(raw: GitHubContributor): Contributor | null {
  if (raw.type !== "User" || !raw.login || !raw.html_url || !raw.avatar_url) return null;
  return {
    login: raw.login,
    url: raw.html_url,
    avatarUrl: raw.avatar_url,
    contributions: raw.contributions ?? 0,
  };
}

export async function getContributors(): Promise<Contributor[]> {
  try {
    const headers: Record<string, string> = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

    const res = await fetch(CONTRIBUTORS_API_URL, { headers, next: { revalidate: REVALIDATE_SECONDS } });
    if (!res.ok) return FALLBACK_CONTRIBUTORS;

    const data: unknown = await res.json();
    if (!Array.isArray(data)) return FALLBACK_CONTRIBUTORS;

    const contributors = (data as GitHubContributor[])
      .map(toContributor)
      .filter((c): c is Contributor => c !== null)
      .sort((a, b) => b.contributions - a.contributions);

    return contributors.length > 0 ? contributors : FALLBACK_CONTRIBUTORS;
  } catch {
    return FALLBACK_CONTRIBUTORS;
  }
}
