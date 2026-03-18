/**
 * Context Recovery — Cross-session intelligence for seamless work resumption
 *
 * Tools:
 *   - getSessionHistory: What happened in past sessions for an issue
 *   - recoverContext: Load everything needed to resume work — previous plans,
 *     decisions, PR state, review feedback, event timeline
 */

import { getIssue, type PMEvent } from "./db.js";
import {
  getDecisions,
  getOutcomes,
  getEvents,
} from "./memory.js";
import { getIssueDependencies } from "./graph.js";
import { predictCompletion, predictRework } from "./predict.js";
import { execSync } from "child_process";

// ─── Types ───────────────────────────────────────────────

interface SessionEvent {
  timestamp: string;
  event: string;
  detail: string;
}

interface SessionHistoryResult {
  issueNumber: number;
  title: string;
  totalSessions: number;
  totalEvents: number;
  timeline: SessionEvent[];
  workflowTransitions: Array<{
    from: string;
    to: string;
    timestamp: string;
  }>;
  decisions: Array<{
    timestamp: string;
    decision: string;
    rationale: string | null;
  }>;
  outcomes: Array<{
    timestamp: string;
    result: string;
    summary: string | null;
    lessons: string | null;
  }>;
  sessionGaps: Array<{
    from: string;
    to: string;
    gapDays: number;
  }>;
  summary: string;
}

// ─── AC + Review Gate Helpers ─────────────────────────────

/** Parse acceptance criteria checkboxes from issue body */
function parseACStatus(body: string | null): { acChecked: number; acTotal: number } {
  if (!body) return { acChecked: 0, acTotal: 0 };

  // Find ## Acceptance Criteria section (case-insensitive, stops at next heading or HR or end)
  const acMatch = body.match(/## Acceptance Criteria\s*\n([\s\S]*?)(?=\n##|\n---|$)/i);
  if (!acMatch) return { acChecked: 0, acTotal: 0 };

  const section = acMatch[1];
  const checked = (section.match(/- \[x\]/gi) || []).length;
  const unchecked = (section.match(/- \[ \]/g) || []).length;

  return { acChecked: checked, acTotal: checked + unchecked };
}

type ReviewGateStatus = "not_started" | "in_progress" | "passed" | "failed";

/** Determine review gate status from events (newest-first order expected) */
function getReviewGateStatus(events: PMEvent[]): ReviewGateStatus {
  // Look for review-related events
  const reviewEvents = events.filter(e =>
    e.event_type === "review_outcome" ||
    e.to_value?.includes("APPROVED") ||
    e.to_value?.includes("BLOCKED") ||
    e.to_value?.includes("CHANGES_NEEDED") ||
    e.to_value?.includes("CHANGES_REQUESTED")
  );

  if (reviewEvents.length === 0) return "not_started";

  const latest = reviewEvents[0]; // events are newest-first from getEvents()
  if (latest.to_value?.includes("APPROVED")) return "passed";
  if (
    latest.to_value?.includes("BLOCKED") ||
    latest.to_value?.includes("CHANGES_NEEDED") ||
    latest.to_value?.includes("CHANGES_REQUESTED")
  ) return "failed";

  return "in_progress";
}

interface PRState {
  number: number;
  title: string;
  state: string;
  draft: boolean;
  reviewDecision: string | null;
  reviewComments: Array<{
    author: string;
    body: string;
    createdAt: string;
  }>;
  files: number;
  additions: number;
  deletions: number;
}

interface ContextRecovery {
  issueNumber: number;
  title: string;
  currentState: {
    workflow: string | null;
    issueState: string;
    labels: string[];
    assignees: string[];
  };
  acceptanceCriteria: {
    acChecked: number;
    acTotal: number;
  };
  reviewGateStatus: ReviewGateStatus;
  previousPlans: Array<{
    path: string;
    lastModified: string;
    preview: string;
  }>;
  pr: PRState | null;
  reviewFeedback: string[];
  decisions: Array<{
    timestamp: string;
    decision: string;
    rationale: string | null;
  }>;
  recentEvents: SessionEvent[];
  dependencies: {
    blockedBy: Array<{ number: number; title: string; resolved: boolean }>;
    blocks: Array<{ number: number; title: string }>;
    isUnblocked: boolean;
  } | null;
  predictions: {
    completionP50: string | null;
    reworkProbability: number | null;
    riskScore: number | null;
  };
  issueComments: Array<{
    author: string;
    body: string;
    createdAt: string;
  }>;
  resumptionGuide: {
    mode: string;
    nextSteps: string[];
    warnings: string[];
    contextFiles: string[];
  };
  summary: string;
}

// ─── get_session_history ─────────────────────────────────

export async function getSessionHistory(
  issueNumber: number,
  viewMode: "default" | "timeline" = "default"
): Promise<SessionHistoryResult> {
  const [statusOrNull, events, decisions, outcomes] = await Promise.all([
    getIssue(issueNumber),
    getEvents(500, { issueNumber }),
    getDecisions(50, issueNumber),
    getOutcomes(20, { issueNumber }),
  ]);

  if (!statusOrNull) {
    throw new Error(`Issue #${issueNumber} not found in local database. Run 'pm sync' first.`);
  }
  const status = statusOrNull;

  // Build timeline
  const timeline: SessionEvent[] = events.map((e) => ({
    timestamp: e.timestamp,
    event: e.event_type,
    detail:
      e.to_value ||
      (e.from_value && e.to_value
        ? `${e.from_value} → ${e.to_value}`
        : (e.metadata as any)?.tool || ""),
  }));

  // Extract workflow transitions
  const workflowTransitions = events
    .filter((e) => e.event_type === "workflow_transition" && e.from_value && e.to_value)
    .map((e) => ({
      from: e.from_value!,
      to: e.to_value!,
      timestamp: e.timestamp,
    }));

  // Detect session gaps (>24h between events)
  const sessionGaps: SessionHistoryResult["sessionGaps"] = [];
  const sortedEvents = [...events].sort(
    (a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
  );

  for (let i = 1; i < sortedEvents.length; i++) {
    const prev = new Date(sortedEvents[i - 1].timestamp);
    const curr = new Date(sortedEvents[i].timestamp);
    const gapMs = curr.getTime() - prev.getTime();
    const gapDays = Math.round((gapMs / 86400000) * 10) / 10;
    if (gapDays >= 1) {
      sessionGaps.push({
        from: sortedEvents[i - 1].timestamp,
        to: sortedEvents[i].timestamp,
        gapDays,
      });
    }
  }

  // Count approximate sessions (clusters of events within 4 hours)
  let sessionCount = 0;
  let lastEventTime = 0;
  for (const e of sortedEvents) {
    const t = new Date(e.timestamp).getTime();
    if (t - lastEventTime > 4 * 3600000) sessionCount++;
    lastEventTime = t;
  }

  const summary =
    `Issue #${issueNumber} (${status.title}): ${sessionCount} session${sessionCount !== 1 ? "s" : ""}, ` +
    `${events.length} events, ${workflowTransitions.length} workflow transitions, ` +
    `${decisions.length} decision${decisions.length !== 1 ? "s" : ""} recorded. ` +
    `${sessionGaps.length > 0 ? `${sessionGaps.length} gap${sessionGaps.length !== 1 ? "s" : ""} >1 day. ` : ""}` +
    `${outcomes.length > 0 ? `Latest outcome: ${outcomes[0].result}.` : "No outcomes recorded yet."}`;

  // Timeline view: aggregate all event types into a single chronological view
  if (viewMode === "timeline") {
    const timelineEntries: SessionEvent[] = [];

    // State transitions
    for (const e of events) {
      if (e.event_type === "workflow_change" && e.from_value && e.to_value) {
        timelineEntries.push({
          timestamp: e.timestamp,
          event: "state_transition",
          detail: `${e.from_value} → ${e.to_value}`,
        });
      } else if (e.event_type === "release_work") {
        const meta = typeof e.metadata === "string" ? JSON.parse(e.metadata) : e.metadata;
        timelineEntries.push({
          timestamp: e.timestamp,
          event: "release",
          detail: `Released: ${meta?.reason || "unknown reason"}`,
        });
      } else if (e.event_type === "review_outcome") {
        timelineEntries.push({
          timestamp: e.timestamp,
          event: "review",
          detail: `Review: ${e.to_value || "recorded"}`,
        });
      }
    }

    // Decisions
    for (const d of decisions) {
      timelineEntries.push({
        timestamp: d.timestamp,
        event: "decision",
        detail: d.decision,
      });
    }

    // Outcomes
    for (const o of outcomes) {
      timelineEntries.push({
        timestamp: o.timestamp,
        event: "outcome",
        detail: `${o.result}: ${o.approach_summary || ""}`,
      });
    }

    // Sort chronologically
    timelineEntries.sort(
      (a, b) =>
        new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    );

    const timelineSummary =
      `Provenance timeline for #${issueNumber}: ${timelineEntries.length} entries spanning ` +
      `${sessionCount} session${sessionCount !== 1 ? "s" : ""}. ` +
      `${workflowTransitions.length} state transitions, ${decisions.length} decisions, ${outcomes.length} outcomes.`;

    return {
      issueNumber,
      title: status.title,
      totalSessions: sessionCount,
      totalEvents: events.length,
      timeline: timelineEntries.slice(-100),
      workflowTransitions,
      decisions: decisions.map((d) => ({
        timestamp: d.timestamp,
        decision: d.decision,
        rationale: d.rationale,
      })),
      outcomes: outcomes.map((o) => ({
        timestamp: o.timestamp,
        result: o.result,
        summary: o.approach_summary,
        lessons: o.lessons,
      })),
      sessionGaps,
      summary: timelineSummary,
    };
  }

  return {
    issueNumber,
    title: status.title,
    totalSessions: sessionCount,
    totalEvents: events.length,
    timeline: timeline.slice(-50), // Last 50 events
    workflowTransitions,
    decisions: decisions.map((d) => ({
      timestamp: d.timestamp,
      decision: d.decision,
      rationale: d.rationale,
    })),
    outcomes: outcomes.map((o) => ({
      timestamp: o.timestamp,
      result: o.result,
      summary: o.approach_summary,
      lessons: o.lessons,
    })),
    sessionGaps,
    summary,
  };
}

// ─── recover_context ─────────────────────────────────────

export async function recoverContext(
  issueNumber: number
): Promise<ContextRecovery> {
  // Gather everything in parallel
  const [statusOrNull, events, decisions, outcomes, deps] = await Promise.all([
    getIssue(issueNumber),
    getEvents(100, { issueNumber }),
    getDecisions(20, issueNumber),
    getOutcomes(5, { issueNumber }),
    getIssueDependencies(issueNumber).catch(() => null),
  ]);

  if (!statusOrNull) {
    throw new Error(`Issue #${issueNumber} not found in local database. Run 'pm sync' first.`);
  }
  const status = statusOrNull;

  // Try to get predictions
  let completionP50: string | null = null;
  let reworkProbability: number | null = null;
  let riskScore: number | null = null;
  try {
    const completion = await predictCompletion(issueNumber);
    completionP50 = completion.prediction?.expectedDate?.p50 || null;
    riskScore = completion.riskScore;
  } catch {
    // Predictions not available
  }
  try {
    const rework = await predictRework(issueNumber);
    reworkProbability = rework.reworkProbability;
  } catch {
    // Rework prediction not available
  }

  // Find linked PRs
  let pr: PRState | null = null;
  try {
    const prSearch = execSync(
      `gh pr list --search "Fixes #${issueNumber}" --json number,title,state,isDraft,reviewDecision,files,additions,deletions --limit 1 2>/dev/null`,
      { encoding: "utf-8" }
    );
    const prs = JSON.parse(prSearch);
    if (prs.length > 0) {
      const p = prs[0];
      // Get review comments
      let reviewComments: PRState["reviewComments"] = [];
      try {
        const commentsJson = execSync(
          `gh pr view ${p.number} --json comments --jq '.comments[] | {author: .author.login, body: .body, createdAt: .createdAt}' 2>/dev/null`,
          { encoding: "utf-8" }
        );
        reviewComments = commentsJson
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((line) => {
            try {
              return JSON.parse(line);
            } catch {
              return null;
            }
          })
          .filter(Boolean) as PRState["reviewComments"];
      } catch {
        // Comments not available
      }

      pr = {
        number: p.number,
        title: p.title,
        state: p.state,
        draft: p.isDraft || false,
        reviewDecision: p.reviewDecision || null,
        reviewComments,
        files: p.files?.length || 0,
        additions: p.additions || 0,
        deletions: p.deletions || 0,
      };
    }
  } catch {
    // PR search failed
  }

  // Get issue comments
  let issueComments: ContextRecovery["issueComments"] = [];
  try {
    const commentsJson = execSync(
      `gh issue view ${issueNumber} --json comments --jq '.comments[] | {author: .author.login, body: .body, createdAt: .createdAt}' 2>/dev/null`,
      { encoding: "utf-8" }
    );
    issueComments = commentsJson
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean) as ContextRecovery["issueComments"];
  } catch {
    // Comments not available
  }

  // Find previous plans
  const previousPlans: ContextRecovery["previousPlans"] = [];
  try {
    const planSearch = execSync(
      `find .claude/plans -name '*.md' -exec grep -l "#${issueNumber}" {} \\; 2>/dev/null | head -5`,
      { encoding: "utf-8" }
    );
    for (const path of planSearch.trim().split("\n").filter(Boolean)) {
      try {
        const stat = execSync(`stat -f '%m' "${path}" 2>/dev/null || stat -c '%Y' "${path}" 2>/dev/null`, {
          encoding: "utf-8",
        }).trim();
        const content = execSync(`head -20 "${path}" 2>/dev/null`, {
          encoding: "utf-8",
        });
        previousPlans.push({
          path,
          lastModified: new Date(parseInt(stat) * 1000).toISOString(),
          preview: content.trim().substring(0, 500),
        });
      } catch {
        previousPlans.push({
          path,
          lastModified: "unknown",
          preview: "(could not read)",
        });
      }
    }
  } catch {
    // No plans found
  }

  // Extract review feedback from PR comments
  const reviewFeedback: string[] = [];
  if (pr?.reviewComments) {
    for (const comment of pr.reviewComments) {
      if (comment.body.length > 20) {
        reviewFeedback.push(
          `@${comment.author} (${comment.createdAt.split("T")[0]}): ${comment.body.substring(0, 200)}`
        );
      }
    }
  }

  // Parse acceptance criteria from issue body
  const acceptanceCriteria = parseACStatus(status.body);

  // Determine review gate status from events
  const reviewGateStatus = getReviewGateStatus(events);

  // Build resumption guide
  const nextSteps: string[] = [];
  const warnings: string[] = [];
  const contextFiles: string[] = [];

  // Determine mode
  let mode = "unknown";
  if (!status.workflow) {
    mode = "NOT_IN_PROJECT";
    nextSteps.push("Add issue to project first");
  } else if (status.workflow === "Active") {
    mode = "CONTINUE";
    if (pr) {
      nextSteps.push(`PR #${pr.number} exists — continue implementation`);
      if (pr.reviewDecision === "CHANGES_REQUESTED") {
        mode = "REWORK";
        nextSteps.push("Address review feedback before re-submitting");
      }
    } else {
      nextSteps.push("No PR yet — create branch and implement");
    }
  } else if (status.workflow === "Review") {
    mode = "REVIEW";
    nextSteps.push("Waiting for review — check PR status");
  } else if (status.workflow === "Rework") {
    mode = "REWORK";
    nextSteps.push("Address review feedback");
    if (reviewFeedback.length > 0) {
      nextSteps.push(`${reviewFeedback.length} review comments to address`);
    }
  } else if (status.workflow === "Done") {
    mode = "DONE";
    nextSteps.push("Issue is complete — no action needed");
  } else if (
    status.workflow === "Ready" ||
    status.workflow === "Backlog"
  ) {
    mode = "START";
    nextSteps.push("Move to Active and begin implementation");
  }

  // Warnings
  if (deps && !deps.isUnblocked) {
    warnings.push(
      `Issue is blocked by: ${deps.blockedBy.filter((b) => !b.resolved).map((b) => `#${b.number}`).join(", ")}`
    );
  }
  if (reworkProbability !== null && reworkProbability > 0.5) {
    warnings.push(
      `High rework probability (${Math.round(reworkProbability * 100)}%) — review carefully before submitting`
    );
  }
  if (riskScore !== null && riskScore > 70) {
    warnings.push(`High completion risk (${riskScore}/100)`);
  }

  // AC-related warnings
  if (acceptanceCriteria.acTotal > 0 && acceptanceCriteria.acChecked < acceptanceCriteria.acTotal) {
    warnings.push(
      `Unchecked acceptance criteria: ${acceptanceCriteria.acChecked}/${acceptanceCriteria.acTotal} complete`
    );
  }

  // Review gate warnings
  if (reviewGateStatus === "failed") {
    warnings.push("Review gate failed — changes requested or blocked");
  }

  // Stale branch warning: if issue is Active but no events in 7+ days
  if (status.workflow === "Active" && events.length > 0) {
    const latestEvent = events[0]; // newest-first
    const latestTime = new Date(latestEvent.timestamp).getTime();
    const daysSinceLastEvent = (Date.now() - latestTime) / (1000 * 60 * 60 * 24);
    if (daysSinceLastEvent > 7) {
      warnings.push(
        `Stale: no events for ${Math.round(daysSinceLastEvent)} days while Active`
      );
    }
  }

  // Missing plan warning for Active issues
  if (
    (status.workflow === "Active" || status.workflow === "Ready") &&
    previousPlans.length === 0
  ) {
    warnings.push("No plan file found — consider creating a plan before implementation");
  }

  // Context files based on area
  const area = status.labels.find((l) => l.startsWith("area:"))?.replace("area:", "") ?? null;
  if (area) {
    const areaFiles: Record<string, string[]> = {
      frontend: ["docs/development/LOCAL_DEV.md", "docs/architecture/OVERVIEW.md"],
      backend: ["docs/architecture/DATABASE.md", "docs/architecture/OVERVIEW.md"],
      contracts: ["docs/contracts/GAME_CONTRACT_INTERFACE.md"],
      infra: ["docs/ENV_WORKFLOW.md", "docs/SECRETS.md"],
    };
    contextFiles.push(...(areaFiles[area] || []));
  }
  contextFiles.push("CLAUDE.md", "docs/PM_PLAYBOOK.md");

  const recentEvents: SessionEvent[] = events.slice(-20).map((e) => ({
    timestamp: e.timestamp,
    event: e.event_type,
    detail:
      e.to_value ||
      (e.from_value && e.to_value
        ? `${e.from_value} → ${e.to_value}`
        : (e.metadata as any)?.tool || ""),
  }));

  const acSummary = acceptanceCriteria.acTotal > 0
    ? `AC: ${acceptanceCriteria.acChecked}/${acceptanceCriteria.acTotal}. `
    : "";
  const reviewGateSummary = reviewGateStatus !== "not_started"
    ? `Review gate: ${reviewGateStatus}. `
    : "";

  const summary =
    `Issue #${issueNumber} (${status.title}) — Mode: ${mode}. ` +
    `${pr ? `PR #${pr.number} (${pr.state}${pr.reviewDecision ? `, ${pr.reviewDecision}` : ""}). ` : "No PR. "}` +
    `${acSummary}${reviewGateSummary}` +
    `${decisions.length} decisions, ${previousPlans.length} plans on disk. ` +
    `${reviewFeedback.length > 0 ? `${reviewFeedback.length} review comments to address. ` : ""}` +
    `${warnings.length > 0 ? `Warnings: ${warnings.join("; ")}. ` : ""}` +
    `Next: ${nextSteps[0] || "determine approach"}.`;

  return {
    issueNumber,
    title: status.title,
    currentState: {
      workflow: status.workflow,
      issueState: status.state,
      labels: status.labels,
      assignees: status.assignees,
    },
    acceptanceCriteria,
    reviewGateStatus,
    previousPlans,
    pr,
    reviewFeedback,
    decisions: decisions.map((d) => ({
      timestamp: d.timestamp,
      decision: d.decision,
      rationale: d.rationale,
    })),
    recentEvents,
    dependencies: deps
      ? {
          blockedBy: deps.blockedBy.map((b) => ({
            number: b.number,
            title: b.title,
            resolved: b.resolved,
          })),
          blocks: deps.blocks.map((b) => ({
            number: b.number,
            title: b.title,
          })),
          isUnblocked: deps.isUnblocked,
        }
      : null,
    predictions: {
      completionP50,
      reworkProbability,
      riskScore,
    },
    issueComments,
    resumptionGuide: {
      mode,
      nextSteps,
      warnings,
      contextFiles,
    },
    summary,
  };
}
