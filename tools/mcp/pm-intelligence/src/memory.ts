/**
 * Memory system — reads and writes JSONL decision/outcome logs.
 *
 * Integrates with the pm-record.sh JSONL format for cross-session learning.
 * The MCP server can both read memory (for context) and write memory
 * (recording decisions/outcomes without shelling out to pm-record.sh).
 */

import { readFile, appendFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

/** Find the repo root */
async function getRepoRoot(): Promise<string> {
  const { stdout } = await execFileAsync("git", [
    "rev-parse",
    "--show-toplevel",
  ]);
  return stdout.trim();
}

// ─── Types ──────────────────────────────────────────────

export interface Decision {
  timestamp: string;
  issue_number: number | null;
  area: string | null;
  type: string;
  decision: string;
  rationale: string | null;
  alternatives_considered: string[];
  files: string[];
}

export interface Outcome {
  timestamp: string;
  issue_number: number;
  pr_number: number | null;
  result: string;
  review_rounds: number | null;
  rework_reasons: string[];
  area: string | null;
  approach_summary: string | null;
  lessons: string | null;
}

export interface BoardCache {
  timestamp: string;
  active: number;
  review: number;
  rework: number;
  done: number;
  backlog: number;
  ready: number;
}

// ─── Read Operations ────────────────────────────────────

/** Read JSONL file and return parsed lines */
async function readJsonl<T>(filePath: string): Promise<T[]> {
  if (!existsSync(filePath)) return [];
  const content = await readFile(filePath, "utf-8");
  return content
    .trim()
    .split("\n")
    .filter((line) => line.trim())
    .map((line) => JSON.parse(line) as T);
}

/** Get recent decisions, optionally filtered by issue */
export async function getDecisions(
  limit = 20,
  issueNumber?: number
): Promise<Decision[]> {
  const root = await getRepoRoot();
  const path = `${root}/.claude/memory/decisions.jsonl`;
  let decisions = await readJsonl<Decision>(path);

  if (issueNumber !== undefined) {
    decisions = decisions.filter((d) => d.issue_number === issueNumber);
  }

  return decisions.slice(-limit);
}

/** Get recent outcomes, optionally filtered by issue or area */
export async function getOutcomes(
  limit = 20,
  filters?: { issueNumber?: number; area?: string; result?: string }
): Promise<Outcome[]> {
  const root = await getRepoRoot();
  const path = `${root}/.claude/memory/outcomes.jsonl`;
  let outcomes = await readJsonl<Outcome>(path);

  if (filters?.issueNumber !== undefined) {
    outcomes = outcomes.filter((o) => o.issue_number === filters.issueNumber);
  }
  if (filters?.area) {
    outcomes = outcomes.filter((o) => o.area === filters.area);
  }
  if (filters?.result) {
    outcomes = outcomes.filter((o) => o.result === filters.result);
  }

  return outcomes.slice(-limit);
}

/** Get cached board state */
export async function getBoardCache(): Promise<BoardCache | null> {
  const root = await getRepoRoot();
  const path = `${root}/.claude/memory/board-cache.json`;
  if (!existsSync(path)) return null;

  const content = await readFile(path, "utf-8");
  const cache = JSON.parse(content) as BoardCache;

  // Check if cache is stale (>1 hour)
  const age = Date.now() - new Date(cache.timestamp).getTime();
  if (age > 60 * 60 * 1000) return null;

  return cache;
}

// ─── Write Operations ───────────────────────────────────

/** Record a decision to JSONL */
export async function recordDecision(decision: {
  issueNumber?: number;
  area?: string;
  type?: string;
  decision: string;
  rationale?: string;
  alternatives?: string[];
  files?: string[];
}): Promise<void> {
  const root = await getRepoRoot();
  const dir = `${root}/.claude/memory`;
  await mkdir(dir, { recursive: true });

  const record: Decision = {
    timestamp: new Date().toISOString(),
    issue_number: decision.issueNumber ?? null,
    area: decision.area ?? null,
    type: decision.type ?? "architectural",
    decision: decision.decision,
    rationale: decision.rationale ?? null,
    alternatives_considered: decision.alternatives ?? [],
    files: decision.files ?? [],
  };

  await appendFile(`${dir}/decisions.jsonl`, JSON.stringify(record) + "\n");
}

/** Record an outcome to JSONL */
export async function recordOutcome(outcome: {
  issueNumber: number;
  prNumber?: number;
  result: string;
  reviewRounds?: number;
  reworkReasons?: string[];
  area?: string;
  summary?: string;
  lessons?: string;
}): Promise<void> {
  const root = await getRepoRoot();
  const dir = `${root}/.claude/memory`;
  await mkdir(dir, { recursive: true });

  const record: Outcome = {
    timestamp: new Date().toISOString(),
    issue_number: outcome.issueNumber,
    pr_number: outcome.prNumber ?? null,
    result: outcome.result,
    review_rounds: outcome.reviewRounds ?? null,
    rework_reasons: outcome.reworkReasons ?? [],
    area: outcome.area ?? null,
    approach_summary: outcome.summary ?? null,
    lessons: outcome.lessons ?? null,
  };

  await appendFile(`${dir}/outcomes.jsonl`, JSON.stringify(record) + "\n");
}

/** Update board cache */
export async function updateBoardCache(
  state: Omit<BoardCache, "timestamp">
): Promise<void> {
  const root = await getRepoRoot();
  const dir = `${root}/.claude/memory`;
  await mkdir(dir, { recursive: true });

  const cache: BoardCache = {
    timestamp: new Date().toISOString(),
    ...state,
  };

  await writeFile(`${dir}/board-cache.json`, JSON.stringify(cache, null, 2));
}

// ─── Analytics ──────────────────────────────────────────

export interface MemoryInsights {
  totalDecisions: number;
  totalOutcomes: number;
  reworkRate: number;
  averageReviewRounds: number;
  topAreas: Array<{ area: string; count: number }>;
  recentLessons: string[];
  decisionPatterns: Array<{ type: string; count: number }>;
}

/** Analyze memory for patterns and insights */
export async function getInsights(): Promise<MemoryInsights> {
  const decisions = await getDecisions(1000);
  const outcomes = await getOutcomes(1000);

  // Rework rate
  const totalResults = outcomes.length;
  const reworkCount = outcomes.filter((o) => o.result === "rework").length;
  const reworkRate = totalResults > 0 ? reworkCount / totalResults : 0;

  // Average review rounds
  const withRounds = outcomes.filter((o) => o.review_rounds !== null);
  const avgRounds =
    withRounds.length > 0
      ? withRounds.reduce((sum, o) => sum + (o.review_rounds || 0), 0) /
        withRounds.length
      : 0;

  // Top areas
  const areaCounts: Record<string, number> = {};
  for (const o of outcomes) {
    if (o.area) areaCounts[o.area] = (areaCounts[o.area] || 0) + 1;
  }
  const topAreas = Object.entries(areaCounts)
    .map(([area, count]) => ({ area, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);

  // Recent lessons
  const recentLessons = outcomes
    .filter((o) => o.lessons)
    .slice(-5)
    .map((o) => o.lessons!);

  // Decision type patterns
  const typeCounts: Record<string, number> = {};
  for (const d of decisions) {
    typeCounts[d.type] = (typeCounts[d.type] || 0) + 1;
  }
  const decisionPatterns = Object.entries(typeCounts)
    .map(([type, count]) => ({ type, count }))
    .sort((a, b) => b.count - a.count);

  return {
    totalDecisions: decisions.length,
    totalOutcomes: outcomes.length,
    reworkRate: Math.round(reworkRate * 100) / 100,
    averageReviewRounds: Math.round(avgRounds * 10) / 10,
    topAreas,
    recentLessons,
    decisionPatterns,
  };
}
