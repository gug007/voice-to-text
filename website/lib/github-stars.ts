import { REPO_URL } from "@/lib/constants";

const REPO_API_URL = REPO_URL.replace("https://github.com/", "https://api.github.com/repos/");

const REVALIDATE_SECONDS = 60 * 60;

/** The repo's stargazer count, or null when the GitHub API is unreachable or rate-limited. */
export async function getStarCount(): Promise<number | null> {
  try {
    const headers: Record<string, string> = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

    const res = await fetch(REPO_API_URL, { headers, next: { revalidate: REVALIDATE_SECONDS } });
    if (!res.ok) return null;

    const data = (await res.json()) as { stargazers_count?: unknown };
    return typeof data.stargazers_count === "number" ? data.stargazers_count : null;
  } catch {
    return null;
  }
}

export function formatStarCount(n: number): string {
  return n >= 1000 ? `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k` : String(n);
}
