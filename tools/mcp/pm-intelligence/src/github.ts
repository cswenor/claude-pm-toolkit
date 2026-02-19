/**
 * GitHub API integration via `gh` CLI.
 *
 * Uses the gh CLI for all GitHub operations. This keeps dependencies minimal
 * (no Octokit) and leverages the user's existing gh authentication.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { PM_CONFIG } from "./config.js";

const execFileAsync = promisify(execFile);

/** Execute a gh CLI command and return stdout */
async function gh(args: string[]): Promise<string> {
  const { stdout } = await execFileAsync("gh", args, {
    timeout: 30_000,
    maxBuffer: 10 * 1024 * 1024,
  });
  return stdout.trim();
}

/** Execute a GraphQL query via gh api */
async function graphql(query: string, variables: Record<string, unknown> = {}): Promise<unknown> {
  const args = ["api", "graphql", "-f", `query=${query}`];
  for (const [key, value] of Object.entries(variables)) {
    if (typeof value === "number") {
      args.push("-F", `${key}=${value}`);
    } else {
      args.push("-f", `${key}=${String(value)}`);
    }
  }
  const result = await gh(args);
  return JSON.parse(result);
}

// ─── Repo Detection ──────────────────────────────────────

/** Get the repo name from git remote */
export async function getRepoName(): Promise<string> {
  const { stdout } = await execFileAsync("git", [
    "remote",
    "get-url",
    "origin",
  ]);
  const url = stdout.trim();
  const match = url.match(/(?:github\.com[:/])([^/]+\/[^/.\s]+)/);
  if (!match) throw new Error(`Cannot parse repo from remote URL: ${url}`);
  const parts = match[1].replace(/\.git$/, "").split("/");
  return parts[1];
}

// ─── Issue Queries ────────────────────────────────────────

export interface IssueStatus {
  number: number;
  title: string;
  state: string;
  assignees: string[];
  labels: string[];
  workflow: string | null;
  priority: string | null;
  area: string | null;
}

/** Get detailed issue status including project board fields */
export async function getIssueStatus(issueNumber: number): Promise<IssueStatus> {
  const repo = await getRepoName();
  const result = (await graphql(
    `query($owner: String!, $repo: String!, $issue: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $issue) {
          title
          state
          assignees(first: 5) { nodes { login } }
          labels(first: 20) { nodes { name } }
          projectItems(first: 5) {
            nodes {
              project { number }
              fieldValueByName(name: "Workflow") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              priority: fieldValueByName(name: "Priority") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              area: fieldValueByName(name: "Area") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
            }
          }
        }
      }
    }`,
    { owner: PM_CONFIG.owner, repo, issue: issueNumber }
  )) as { data: { repository: { issue: Record<string, unknown> | null } } };

  const issue = result.data?.repository?.issue;
  if (!issue) throw new Error(`Issue #${issueNumber} not found`);

  const projectItem = (issue.projectItems as { nodes: Array<Record<string, unknown>> })
    ?.nodes?.find(
      (n: Record<string, unknown>) =>
        (n.project as { number: number })?.number === PM_CONFIG.projectNumber
    );

  return {
    number: issueNumber,
    title: issue.title as string,
    state: issue.state as string,
    assignees: ((issue.assignees as { nodes: Array<{ login: string }> })?.nodes || []).map(
      (n) => n.login
    ),
    labels: ((issue.labels as { nodes: Array<{ name: string }> })?.nodes || []).map(
      (n) => n.name
    ),
    workflow:
      (projectItem?.fieldValueByName as { name: string })?.name ?? null,
    priority:
      (projectItem?.priority as { name: string })?.name ?? null,
    area:
      (projectItem?.area as { name: string })?.name ?? null,
  };
}

// ─── Board Queries ────────────────────────────────────────

export interface BoardSummary {
  total: number;
  byWorkflow: Record<string, number>;
  byPriority: Record<string, number>;
  activeItems: Array<{ number: number; title: string; assignees: string[] }>;
  reviewItems: Array<{ number: number; title: string }>;
  reworkItems: Array<{ number: number; title: string }>;
  staleItems: Array<{ number: number; title: string; daysSinceUpdate: number }>;
  healthScore: number;
}

/** Get full project board summary with health metrics */
export async function getBoardSummary(): Promise<BoardSummary> {
  const raw = await gh([
    "project",
    "item-list",
    String(PM_CONFIG.projectNumber),
    "--owner",
    PM_CONFIG.owner,
    "--format",
    "json",
    "--limit",
    "200",
  ]);

  const data = JSON.parse(raw);
  const items: Array<Record<string, unknown>> = data.items || [];

  const byWorkflow: Record<string, number> = {};
  const byPriority: Record<string, number> = {};
  const activeItems: BoardSummary["activeItems"] = [];
  const reviewItems: BoardSummary["reviewItems"] = [];
  const reworkItems: BoardSummary["reworkItems"] = [];
  const staleItems: BoardSummary["staleItems"] = [];

  const now = Date.now();

  for (const item of items) {
    const workflow = (item.workflow as string) || (item.status as string) || "Unknown";
    const priority = (item.priority as string) || "None";
    const title = (item.title as string) || "";
    const number = (item.number as number) || 0;
    const assignees = ((item.assignees as string[]) || []);
    const updatedAt = item.updatedAt as string;

    byWorkflow[workflow] = (byWorkflow[workflow] || 0) + 1;
    byPriority[priority] = (byPriority[priority] || 0) + 1;

    if (workflow === "Active") {
      activeItems.push({ number, title, assignees });
    } else if (workflow === "Review") {
      reviewItems.push({ number, title });
    } else if (workflow === "Rework") {
      reworkItems.push({ number, title });
    }

    // Stale detection: items not updated in 7+ days (excluding Done)
    if (updatedAt && workflow !== "Done") {
      const daysSince = Math.floor(
        (now - new Date(updatedAt).getTime()) / (1000 * 60 * 60 * 24)
      );
      if (daysSince >= 7) {
        staleItems.push({ number, title, daysSinceUpdate: daysSince });
      }
    }
  }

  // Sort stale items by age (oldest first)
  staleItems.sort((a, b) => b.daysSinceUpdate - a.daysSinceUpdate);

  // Health score calculation (0-100)
  const healthScore = calculateHealthScore(byWorkflow, staleItems.length, items.length);

  return {
    total: items.length,
    byWorkflow,
    byPriority,
    activeItems,
    reviewItems,
    reworkItems,
    staleItems: staleItems.slice(0, 10), // Top 10 stalest
    healthScore,
  };
}

/** Calculate a health score (0-100) based on board state */
function calculateHealthScore(
  byWorkflow: Record<string, number>,
  staleCount: number,
  total: number
): number {
  if (total === 0) return 100;

  let score = 100;

  // WIP compliance: penalize Active > 1
  const active = byWorkflow["Active"] || 0;
  if (active > 1) score -= (active - 1) * 15;

  // Rework pileup: penalize rework items
  const rework = byWorkflow["Rework"] || 0;
  if (rework > 0) score -= rework * 10;

  // Review bottleneck: penalize review > 3
  const review = byWorkflow["Review"] || 0;
  if (review > 3) score -= (review - 3) * 5;

  // Backlog bloat: penalize if backlog > 50% of total
  const backlog = byWorkflow["Backlog"] || 0;
  if (total > 0 && backlog / total > 0.5) score -= 10;

  // Stale items: penalize
  if (staleCount > 0) score -= Math.min(staleCount * 3, 20);

  return Math.max(0, Math.min(100, score));
}

// ─── Issue Mutations ──────────────────────────────────────

/** Move an issue to a workflow state on the project board */
export async function moveIssue(
  issueNumber: number,
  targetState: string
): Promise<{ success: boolean; message: string }> {
  const repo = await getRepoName();

  // Get project item ID
  const itemResult = (await graphql(
    `query($owner: String!, $repo: String!, $issue: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $issue) {
          projectItems(first: 20) {
            nodes {
              id
              project { number }
            }
          }
        }
      }
    }`,
    { owner: PM_CONFIG.owner, repo, issue: issueNumber }
  )) as { data: { repository: { issue: { projectItems: { nodes: Array<{ id: string; project: { number: number } }> } } | null } } };

  const issue = itemResult.data?.repository?.issue;
  if (!issue) throw new Error(`Issue #${issueNumber} not found`);

  const projectItem = issue.projectItems.nodes.find(
    (n) => n.project.number === PM_CONFIG.projectNumber
  );
  if (!projectItem) {
    throw new Error(
      `Issue #${issueNumber} not in project #${PM_CONFIG.projectNumber}`
    );
  }

  // Map state to option ID
  const { WORKFLOW_MAP } = await import("./config.js");
  const optionId = WORKFLOW_MAP[targetState];
  if (!optionId) throw new Error(`Invalid state: ${targetState}`);

  // Mutate
  await gh([
    "project",
    "item-edit",
    "--project-id",
    PM_CONFIG.projectId,
    "--id",
    projectItem.id,
    "--field-id",
    PM_CONFIG.fields.workflow,
    "--single-select-option-id",
    optionId,
  ]);

  return {
    success: true,
    message: `Issue #${issueNumber} moved to ${targetState}`,
  };
}

// ─── Velocity ─────────────────────────────────────────────

export interface VelocityMetrics {
  last7Days: { merged: number; closed: number; opened: number };
  last30Days: { merged: number; closed: number; opened: number };
  avgDaysToMerge: number | null;
}

/** Calculate velocity metrics from recent activity */
export async function getVelocity(): Promise<VelocityMetrics> {
  const repo = await getRepoName();
  const fullRepo = `${PM_CONFIG.owner}/${repo}`;

  // Recent merged PRs
  const merged7 = await gh([
    "pr",
    "list",
    "--repo",
    fullRepo,
    "--state",
    "merged",
    "--json",
    "number,mergedAt,createdAt",
    "--limit",
    "50",
  ]);
  const mergedPRs: Array<{ mergedAt: string; createdAt: string }> = JSON.parse(merged7);

  const now = Date.now();
  const day7 = 7 * 24 * 60 * 60 * 1000;
  const day30 = 30 * 24 * 60 * 60 * 1000;

  const merged7Count = mergedPRs.filter(
    (p) => now - new Date(p.mergedAt).getTime() < day7
  ).length;
  const merged30Count = mergedPRs.filter(
    (p) => now - new Date(p.mergedAt).getTime() < day30
  ).length;

  // Average days to merge (from recent PRs)
  const mergeTimes = mergedPRs
    .filter((p) => now - new Date(p.mergedAt).getTime() < day30)
    .map(
      (p) =>
        (new Date(p.mergedAt).getTime() - new Date(p.createdAt).getTime()) /
        (1000 * 60 * 60 * 24)
    );
  const avgDaysToMerge =
    mergeTimes.length > 0
      ? Math.round(
          (mergeTimes.reduce((a, b) => a + b, 0) / mergeTimes.length) * 10
        ) / 10
      : null;

  // Recent issues
  const closed7 = await gh([
    "issue",
    "list",
    "--repo",
    fullRepo,
    "--state",
    "closed",
    "--json",
    "closedAt",
    "--limit",
    "50",
  ]);
  const closedIssues: Array<{ closedAt: string }> = JSON.parse(closed7);
  const closed7Count = closedIssues.filter(
    (i) => now - new Date(i.closedAt).getTime() < day7
  ).length;
  const closed30Count = closedIssues.filter(
    (i) => now - new Date(i.closedAt).getTime() < day30
  ).length;

  const opened = await gh([
    "issue",
    "list",
    "--repo",
    fullRepo,
    "--state",
    "all",
    "--json",
    "createdAt",
    "--limit",
    "50",
  ]);
  const openedIssues: Array<{ createdAt: string }> = JSON.parse(opened);
  const opened7Count = openedIssues.filter(
    (i) => now - new Date(i.createdAt).getTime() < day7
  ).length;
  const opened30Count = openedIssues.filter(
    (i) => now - new Date(i.createdAt).getTime() < day30
  ).length;

  return {
    last7Days: {
      merged: merged7Count,
      closed: closed7Count,
      opened: opened7Count,
    },
    last30Days: {
      merged: merged30Count,
      closed: closed30Count,
      opened: opened30Count,
    },
    avgDaysToMerge,
  };
}
