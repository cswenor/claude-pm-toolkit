#!/usr/bin/env node

/**
 * PM Intelligence MCP Server
 *
 * Exposes project management state, memory, and health metrics as MCP
 * tools and resources. Gives Claude direct access to live project data
 * without shelling out to bash scripts.
 *
 * Tools:
 *   - get_issue_status: Get workflow state, priority, area for an issue
 *   - get_board_summary: Full board with health score and stale items
 *   - move_issue: Transition an issue to a workflow state
 *   - get_velocity: Merge/close/open rates for 7 and 30 day windows
 *   - record_decision: Log an architectural decision to memory
 *   - record_outcome: Log a work outcome to memory
 *   - get_memory_insights: Analytics on rework rate, review patterns, areas
 *   - get_event_stream: Query structured event stream for debugging/analytics
 *   - get_sprint_analytics: Deep sprint analytics (cycle time, bottlenecks, flow)
 *   - suggest_approach: Query past decisions/outcomes for similar work
 *   - check_readiness: Pre-review validation from event stream
 *   - get_history_insights: Git history mining (hotspots, coupling, risk)
 *   - predict_completion: P50/P80/P95 completion dates + risk score
 *   - predict_rework: Rework probability with weighted signals
 *   - get_dora_metrics: DORA metrics (deploy freq, lead time, CFR, MTTR)
 *   - get_knowledge_risk: Bus factor and knowledge decay analysis
 *   - record_review_outcome: Track review finding dispositions
 *   - get_review_calibration: Review hit rate and false positive patterns
 *   - check_decision_decay: Flag stale decisions based on context drift
 *   - simulate_sprint: Monte Carlo sprint throughput simulation
 *   - forecast_backlog: Monte Carlo backlog completion forecast
 *   - detect_scope_creep: Compare plan to actual changes
 *   - get_context_efficiency: AI context waste metrics per issue
 *   - get_workflow_health: Cross-issue health and bottleneck analysis
 *   - analyze_dependency_graph: Full dependency graph with critical path
 *   - get_issue_dependencies: Dependencies for a single issue
 *   - get_team_capacity: Team throughput analysis and sprint forecast
 *   - plan_sprint: AI-powered sprint planning combining all intelligence
 *   - visualize_dependencies: ASCII + Mermaid dependency graph visualization
 *   - get_project_dashboard: Full project health report synthesizing all intelligence
 *   - suggest_next_issue: "What should I work on next?" recommendation engine
 *   - generate_standup: Auto-generate daily standup from recent activity
 *   - generate_retro: Data-driven sprint retrospective
 *   - explain_delay: "Why is this issue slow?" root cause analysis
 *   - compare_estimates: Prediction accuracy tracking and calibration
 *   - detect_patterns: Cross-cutting anomaly detection and early warnings
 *   - triage_issue: One-call issue classification, priority, risk, assignment
 *   - analyze_pr_impact: Pre-merge dependency, knowledge, coupling analysis
 *   - decompose_issue: AI-powered issue decomposition with execution order
 *   - simulate_dependency_change: "What if issue #X slips by N days?"
 *   - generate_release_notes: Automated release notes from merged PRs
 *   - optimize_session: Context-aware session planning and work prioritization
 *   - review_pr: Structured PR analysis with scope, risk, and acceptance criteria
 *   - auto_label: Automatic issue classification from content analysis
 *   - get_session_history: Cross-session event history for an issue
 *   - recover_context: Full context recovery to resume work on an issue
 *   - bulk_triage: Triage all untriaged issues in one call
 *   - bulk_move: Move multiple issues between workflow states
 *   - get_risk_radar: Unified risk assessment synthesizing all intelligence
 *
 * Resources:
 *   - pm://board/overview: Board summary (same as tool, but as resource)
 *   - pm://memory/decisions: Recent decisions
 *   - pm://memory/outcomes: Recent outcomes
 *   - pm://memory/insights: Memory analytics
 *   - pm://analytics/sprint: Sprint analytics for current period
 *   - pm://analytics/dora: DORA performance metrics
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { WORKFLOW_STATES } from "./config.js";
import {
  getIssue,
  getLocalBoardSummary,
  moveIssueWorkflow,
  addDependency,
  getDependencies,
  getCycleTimes,
  type WorkflowState,
} from "./db.js";
import { syncFromGitHub, isSyncStale } from "./sync.js";
import { getVelocity } from "./github.js";
import {
  getDecisions,
  getOutcomes,
  getEvents,
  getBoardCache,
  recordDecision,
  recordOutcome,
  updateBoardCache,
  getInsights,
} from "./memory.js";
import {
  getSprintAnalytics,
  suggestApproach,
  checkReadiness,
} from "./analytics.js";
import { getHistoryInsights } from "./history.js";
import {
  predictCompletion,
  predictRework,
  getDORAMetrics,
  getKnowledgeRisk,
} from "./predict.js";
import {
  recordReviewOutcome,
  getReviewCalibration,
  checkDecisionDecay,
} from "./review-learning.js";
import {
  simulateSprint,
  forecastBacklog,
} from "./simulate.js";
import {
  detectScopeCreep,
  getContextEfficiency,
  getWorkflowHealth,
} from "./guardrails.js";
import {
  analyzeDependencyGraph,
  getIssueDependencies,
} from "./graph.js";
import { getTeamCapacity } from "./capacity.js";
import { planSprint } from "./planner.js";
import { visualizeDependencies } from "./visualize.js";
import { getProjectDashboard } from "./dashboard.js";
import {
  suggestNextIssue,
  generateStandup,
  generateRetro,
} from "./operations.js";
import {
  explainDelay,
  compareEstimates,
} from "./explain.js";
import { detectPatterns } from "./anomaly.js";
import {
  triageIssue,
  analyzePRImpact,
  decomposeIssue,
} from "./triage.js";
import { simulateDependencyChange } from "./whatif.js";
import { generateReleaseNotes } from "./release.js";
import { optimizeSession } from "./session.js";
import { reviewPR, autoLabel } from "./review-intel.js";
import { getSessionHistory, recoverContext } from "./context.js";
import { bulkTriage, bulkMove } from "./batch.js";
import { getRiskRadar } from "./risk-radar.js";

const server = new McpServer({
  name: "pm-intelligence",
  version: "0.15.0",
});

// ─── TOOLS ──────────────────────────────────────────────

server.registerTool(
  "get_issue_status",
  {
    title: "Get Issue Status",
    description:
      "Get the current workflow state, priority, labels, assignees, and dependencies for an issue. Reads from local SQLite database (instant). Run sync_from_github first if data might be stale.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const issue = await getIssue(issueNumber);
      if (!issue) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Issue #${issueNumber} not found in local database. Run sync_from_github to pull from GitHub.`,
            },
          ],
          isError: true,
        };
      }
      const deps = await getDependencies(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify({ ...issue, dependencies: deps }, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_board_summary",
  {
    title: "Project Board Summary",
    description:
      "Get a comprehensive project board summary from local database: issue counts by workflow state, priority distribution, active/review/rework items, blocked items with dependency info, and a health score (0-100). Instant — no GitHub API calls.",
  },
  async () => {
    try {
      const summary = await getLocalBoardSummary();
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(summary, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "move_issue",
  {
    title: "Move Issue",
    description:
      "Move an issue to a new workflow state in the local database. Enforces transition rules and WIP limits. Valid states: Backlog, Ready, Active, Review, Rework, Done. Every transition is recorded in the event log with timestamp.",
    inputSchema: {
      issueNumber: z.number().int().positive().describe("Issue number"),
      targetState: z
        .enum(WORKFLOW_STATES)
        .describe("Target workflow state"),
    },
  },
  async ({ issueNumber, targetState }) => {
    try {
      const result = await moveIssueWorkflow(issueNumber, targetState as WorkflowState);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "sync_from_github",
  {
    title: "Sync from GitHub",
    description:
      "Pull latest issues and PRs from GitHub into the local database. Runs incrementally (only items updated since last sync). Use force=true for a full refresh. Typically runs on session start.",
    inputSchema: {
      force: z.boolean().optional().describe("Force full sync instead of incremental"),
    },
  },
  async ({ force }) => {
    try {
      const result = await syncFromGitHub({ force: force || false });
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "add_dependency",
  {
    title: "Add Dependency",
    description:
      "Add a dependency between two issues. The blocker must be completed before the blocked issue can proceed. Includes cycle detection — will reject if adding the dependency would create a circular dependency.",
    inputSchema: {
      blockerIssue: z.number().int().positive().describe("Issue that blocks"),
      blockedIssue: z.number().int().positive().describe("Issue that is blocked"),
      depType: z.enum(["blocks", "prerequisite", "related"]).optional().describe("Dependency type"),
    },
  },
  async ({ blockerIssue, blockedIssue, depType }) => {
    try {
      await addDependency(blockerIssue, blockedIssue, depType || "blocks");
      return {
        content: [
          { type: "text" as const, text: `Dependency added: #${blockerIssue} blocks #${blockedIssue}` },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_cycle_times",
  {
    title: "Get Cycle Times",
    description:
      "Get cycle times (Active → Done) for completed issues. Shows hours from first Active transition to Done, plus the full workflow path taken. Useful for velocity analysis and estimation.",
    inputSchema: {
      days: z.number().int().positive().optional().describe("Lookback period in days (default: 90)"),
    },
  },
  async ({ days }) => {
    try {
      const times = await getCycleTimes(days || 90);
      const avgHours = times.length > 0
        ? Math.round((times.reduce((s, t) => s + t.hours, 0) / times.length) * 10) / 10
        : null;

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({
              count: times.length,
              averageHours: avgHours,
              averageDays: avgHours ? Math.round((avgHours / 24) * 10) / 10 : null,
              issues: times,
            }, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_velocity",
  {
    title: "Get Velocity Metrics",
    description:
      "Calculate project velocity: PRs merged, issues closed, issues opened for 7-day and 30-day windows. Also returns average days-to-merge for recent PRs.",
  },
  async () => {
    try {
      const metrics = await getVelocity();
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(metrics, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "record_decision",
  {
    title: "Record Decision",
    description:
      "Record an architectural or technical decision to persistent JSONL memory. Decisions are git-tracked and shared across sessions. Use this when making significant choices about approach, libraries, or architecture.",
    inputSchema: {
      decision: z.string().describe("The decision made"),
      issueNumber: z.number().int().optional().describe("Related issue number"),
      area: z
        .enum(["frontend", "backend", "contracts", "infra"])
        .optional()
        .describe("Area of the codebase"),
      type: z
        .enum(["architectural", "library", "approach", "workaround"])
        .optional()
        .describe("Decision type"),
      rationale: z.string().optional().describe("Why this was chosen"),
      alternatives: z
        .array(z.string())
        .optional()
        .describe("Alternatives considered"),
      files: z
        .array(z.string())
        .optional()
        .describe("Affected file paths"),
    },
  },
  async ({ decision, issueNumber, area, type, rationale, alternatives, files }) => {
    try {
      await recordDecision({
        decision,
        issueNumber,
        area,
        type,
        rationale,
        alternatives,
        files,
      });
      return {
        content: [
          {
            type: "text" as const,
            text: `Decision recorded: ${decision}`,
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "record_outcome",
  {
    title: "Record Outcome",
    description:
      "Record a work outcome (merged, rework, reverted, abandoned) to persistent memory. Automatically called on Done transitions, but can be called directly for manual recording with richer detail.",
    inputSchema: {
      issueNumber: z.number().int().positive().describe("Issue number"),
      result: z
        .enum(["merged", "rework", "reverted", "abandoned"])
        .describe("Outcome result"),
      prNumber: z.number().int().optional().describe("PR number"),
      reviewRounds: z
        .number()
        .int()
        .optional()
        .describe("Number of review rounds"),
      reworkReasons: z
        .array(z.string())
        .optional()
        .describe("Reasons for rework"),
      area: z.string().optional().describe("Area"),
      summary: z.string().optional().describe("Approach summary"),
      lessons: z.string().optional().describe("Lessons learned"),
    },
  },
  async ({
    issueNumber,
    result,
    prNumber,
    reviewRounds,
    reworkReasons,
    area,
    summary,
    lessons,
  }) => {
    try {
      await recordOutcome({
        issueNumber,
        result,
        prNumber,
        reviewRounds,
        reworkReasons,
        area,
        summary,
        lessons,
      });
      return {
        content: [
          {
            type: "text" as const,
            text: `Outcome recorded: Issue #${issueNumber} → ${result}`,
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_memory_insights",
  {
    title: "Memory Insights",
    description:
      "Analyze persistent memory for patterns: rework rate, average review rounds, top areas, recent lessons, decision type distribution. Use this to learn from past work and identify improvement areas.",
  },
  async () => {
    try {
      const insights = await getInsights();
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(insights, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_event_stream",
  {
    title: "Get Event Stream",
    description:
      "Query the structured event stream — session starts, state transitions, tool use, errors. Use this for debugging, analytics, and understanding what happened in previous sessions.",
    inputSchema: {
      limit: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Max events to return (default 50, most recent)"),
      issueNumber: z
        .number()
        .int()
        .optional()
        .describe("Filter by issue number"),
      eventType: z
        .string()
        .optional()
        .describe(
          "Filter by event type (session_start, state_change, needs_input, error, etc.)"
        ),
    },
  },
  async ({ limit, issueNumber, eventType }) => {
    try {
      const events = await getEvents(limit ?? 50, { issueNumber, eventType });
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(events, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_sprint_analytics",
  {
    title: "Sprint Analytics",
    description:
      "Deep sprint analytics: cycle time (avg/median/p90), time-in-state analysis, bottleneck detection, flow efficiency, rework patterns, session patterns, and velocity/rework trends comparing current vs previous period. Use this to understand team performance and identify improvement areas.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Sprint period in days (default 14)"),
    },
  },
  async ({ days }) => {
    try {
      const analytics = await getSprintAnalytics(days ?? 14);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(analytics, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "suggest_approach",
  {
    title: "Suggest Approach",
    description:
      "Query past decisions and outcomes to suggest approaches for new work in a specific area. Returns relevant past decisions, lessons learned from similar issues, warnings about common rework reasons, and related issue history. Use this when starting work on a new issue to learn from past experience.",
    inputSchema: {
      area: z
        .enum(["frontend", "backend", "contracts", "infra"])
        .describe("Area of the codebase"),
      keywords: z
        .array(z.string())
        .describe("Keywords describing the work (e.g., ['wallet', 'connection', 'timeout'])"),
      issueNumber: z
        .number()
        .int()
        .optional()
        .describe("Current issue number (for context)"),
      issueTitle: z
        .string()
        .optional()
        .describe("Current issue title (for context)"),
    },
  },
  async ({ area, keywords, issueNumber, issueTitle }) => {
    try {
      const suggestion = await suggestApproach(area, keywords);
      suggestion.issueNumber = issueNumber ?? 0;
      suggestion.issueTitle = issueTitle ?? "";
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(suggestion, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "check_readiness",
  {
    title: "Check Issue Readiness",
    description:
      "Pre-review validation: checks the event stream for an issue to verify that proper workflow was followed — issue was moved to Active, has development sessions, rework was addressed, sufficient development time, and decisions documented. Returns a readiness score (0-100) and specific checks with blocking/warning/info severity. Use this before moving to Review.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to check"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const readiness = await checkReadiness(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(readiness, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_history_insights",
  {
    title: "Git History Insights",
    description:
      "Mine git history for actionable insights: file change hotspots (highest risk areas), coupling analysis (files that always change together), commit patterns (types, scopes, peak times), PR size patterns, and risk area identification. Use this to understand which parts of the codebase are most volatile and where extra care is needed.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("History period in days (default 30)"),
    },
  },
  async ({ days }) => {
    try {
      const insights = await getHistoryInsights(days ?? 30);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(insights, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── PREDICTIVE INTELLIGENCE TOOLS ──────────────────────

server.registerTool(
  "predict_completion",
  {
    title: "Predict Issue Completion",
    description:
      "Predict when an issue will be completed using historical cycle time data. Returns P50/P80/P95 completion dates, a risk score (0-100) with specific risk factors, confidence level based on data quality, and similar issues for comparison. Use this when planning timelines or evaluating if an issue is on track.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to predict completion for"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const prediction = await predictCompletion(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(prediction, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "predict_rework",
  {
    title: "Predict Rework Probability",
    description:
      "Predict the probability that an issue will require rework before it's approved. Analyzes historical rework patterns, development signals (pace, session count, decisions documented), and area-specific baselines. Returns probability (0-1), risk level, weighted signals, and specific mitigations. Use this before moving to Review to catch high-risk PRs early.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to predict rework for"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const prediction = await predictRework(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(prediction, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_dora_metrics",
  {
    title: "DORA Metrics",
    description:
      "Calculate DORA (DevOps Research and Assessment) performance metrics: Deployment Frequency (merge rate), Lead Time for Changes (first commit to merge), Change Failure Rate (rework ratio), Mean Time to Restore (bug fix speed). Each metric is rated elite/high/medium/low per industry benchmarks. Use this for engineering health assessment and team performance tracking.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Analysis period in days (default 30)"),
    },
  },
  async ({ days }) => {
    try {
      const metrics = await getDORAMetrics(days ?? 30);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(metrics, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_knowledge_risk",
  {
    title: "Knowledge Risk Analysis",
    description:
      "Analyze knowledge distribution and bus factor risks across the codebase. Identifies files where knowledge is concentrated in a single contributor (bus factor 1), areas with high knowledge concentration, and files showing knowledge decay (active files that haven't been touched recently). Use this to identify cross-training needs and knowledge sharing priorities.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Analysis period in days (default 90)"),
    },
  },
  async ({ days }) => {
    try {
      const risk = await getKnowledgeRisk(days ?? 90);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(risk, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── REVIEW LEARNING TOOLS ─────────────────────────────

server.registerTool(
  "record_review_outcome",
  {
    title: "Record Review Finding Outcome",
    description:
      "Record the disposition of a review finding (accepted, dismissed, modified, deferred). Called after a review cycle completes. This data is used to calibrate future reviews — tracking which finding types have high hit rates vs high false positive rates. Use this after /pm-review to close the feedback loop.",
    inputSchema: {
      issueNumber: z.number().int().positive().describe("Issue number"),
      prNumber: z.number().int().optional().describe("PR number"),
      findingType: z
        .string()
        .describe("Finding category (e.g., scope_verification, failure_mode, comment_verification, adversarial_edge_case, hook_overhead, path_robustness)"),
      severity: z
        .enum(["blocking", "non_blocking", "suggestion"])
        .describe("Finding severity"),
      disposition: z
        .enum(["accepted", "dismissed", "modified", "deferred"])
        .describe("What happened: accepted (fixed), dismissed (not valid), modified (partially addressed), deferred (tracked for later)"),
      reason: z
        .string()
        .optional()
        .describe("Why this disposition was chosen (especially important for dismissals)"),
      area: z.string().optional().describe("Area of the finding"),
      files: z
        .array(z.string())
        .optional()
        .describe("Files related to the finding"),
    },
  },
  async ({ issueNumber, prNumber, findingType, severity, disposition, reason, area, files }) => {
    try {
      const result = await recordReviewOutcome({
        issueNumber,
        prNumber,
        findingType,
        severity,
        disposition,
        reason,
        area,
        files,
      });
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_review_calibration",
  {
    title: "Review Calibration Report",
    description:
      "Analyze review finding history to calculate hit rates (accepted vs dismissed), identify false positive patterns, and generate calibration data by finding type, severity, and area. Includes trend analysis (improving/stable/declining) and specific recommendations for adjusting review focus. Use this to improve review quality over time.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Analysis period in days (default 90)"),
    },
  },
  async ({ days }) => {
    try {
      const calibration = await getReviewCalibration(days ?? 90);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(calibration, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "check_decision_decay",
  {
    title: "Check Decision Decay",
    description:
      "Detect stale architectural decisions whose context has drifted. Analyzes decisions based on: age, file churn (referenced files changed since), potential supersession (newer decisions in same area), and area activity level. Returns a decay score (0-100) per decision with specific signals and recommendations. Use this periodically to maintain decision hygiene.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Look-back period in days (default 180)"),
    },
  },
  async ({ days }) => {
    try {
      const report = await checkDecisionDecay(days ?? 180);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(report, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── SIMULATION TOOLS ─────────────────────────────────

server.registerTool(
  "simulate_sprint",
  {
    title: "Monte Carlo Sprint Simulation",
    description:
      "Run a Monte Carlo simulation to forecast sprint throughput. Randomly samples from historical cycle time distributions across thousands of trials to produce probabilistic forecasts: 'How many items will we likely finish in N days?' Returns throughput percentiles (P10-P90), completion probability for a target item count, histogram distribution, and data quality assessment. Use this for sprint planning and commitment decisions.",
    inputSchema: {
      itemCount: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Target number of items to evaluate against (default 10)"),
      sprintDays: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Sprint duration in days (default 14)"),
      trials: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Number of simulation trials (default 10000, max 50000)"),
      area: z
        .string()
        .optional()
        .describe("Filter cycle times to a specific area (frontend, backend, contracts, infra)"),
      wipLimit: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Max concurrent items — WIP limit (default 1)"),
    },
  },
  async ({ itemCount, sprintDays, trials, area, wipLimit }) => {
    try {
      const result = await simulateSprint({
        itemCount,
        sprintDays,
        trials,
        area,
        wipLimit,
      });
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "forecast_backlog",
  {
    title: "Monte Carlo Backlog Forecast",
    description:
      "Run a Monte Carlo simulation to answer 'When will we finish these N items?' Produces completion date forecasts with confidence intervals (P50/P80/P95), sprint-by-sprint breakdown showing cumulative progress, and risk analysis (tail risk, variability). Use this for roadmap planning, stakeholder communication, and identifying when a backlog will be cleared.",
    inputSchema: {
      itemCount: z
        .number()
        .int()
        .positive()
        .describe("Total number of items to forecast completing"),
      trials: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Number of simulation trials (default 10000, max 50000)"),
      area: z
        .string()
        .optional()
        .describe("Filter cycle times to a specific area"),
      wipLimit: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Max concurrent items — WIP limit (default 1)"),
    },
  },
  async ({ itemCount, trials, area, wipLimit }) => {
    try {
      const result = await forecastBacklog({
        itemCount,
        trials,
        area,
        wipLimit,
      });
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── GUARDRAIL TOOLS ──────────────────────────────────

server.registerTool(
  "detect_scope_creep",
  {
    title: "Detect Scope Creep",
    description:
      "Compare the implementation plan to actual file changes in the working tree. Identifies out-of-scope files (changed but not in plan), untouched plan files, and calculates a scope creep ratio. Flags infrastructure changes, dependency changes, and patterns that indicate scope mixing. Use this during implementation to catch drift early — before it becomes unmergeable.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Issue number to find the plan for (searches .claude/plans/)"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const report = await detectScopeCreep(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(report, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_context_efficiency",
  {
    title: "Context Efficiency Report",
    description:
      "Measure AI context efficiency for a specific issue: session count, rework cycles, needs-input frequency, error rate, time-in-state metrics, session timing patterns, and an overall efficiency score (0-100). Identifies context waste patterns (long gaps between sessions, excessive rework, high error rates) and provides specific recommendations. Use this after completing an issue to learn from the process, or during work to identify inefficiencies.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to analyze"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const report = await getContextEfficiency(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(report, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_workflow_health",
  {
    title: "Workflow Health Analysis",
    description:
      "Cross-issue workflow health analysis: per-issue health scores, stale issue detection, bottleneck identification (which workflow state has the most stuck items), and systemic pattern detection. Returns a portfolio-level view of project health. Use this during sprint planning, weekly reviews, or when you suspect workflow issues.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Analysis period in days (default 30)"),
    },
  },
  async ({ days }) => {
    try {
      const health = await getWorkflowHealth(days ?? 30);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(health, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── GRAPH & CAPACITY TOOLS ─────────────────────────────

server.registerTool(
  "analyze_dependency_graph",
  {
    title: "Dependency Graph Analysis",
    description:
      "Analyze the full issue dependency graph: build a DAG from blocked-by labels, cross-references, and body/comment markers. Returns critical path (longest unresolved dependency chain), bottleneck issues (blocking the most other work with transitive counts), cycle detection, orphaned blocked issues (all blockers resolved but still marked blocked), and network metrics (depth, density, connected components). Use this for sprint planning, prioritization, and identifying blocked chains.",
  },
  async () => {
    try {
      const result = await analyzeDependencyGraph();
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_issue_dependencies",
  {
    title: "Issue Dependencies",
    description:
      "Get the full dependency tree for a single issue: direct blockers (with resolution status), issues it blocks, full upstream chain (transitive dependencies), full downstream chain (transitive dependents), whether it's unblocked (all blockers resolved), and its execution order position. Use this when evaluating if an issue is ready to work on or understanding its impact on the project.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to analyze"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const result = await getIssueDependencies(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_team_capacity",
  {
    title: "Team Capacity Analysis",
    description:
      "Analyze team throughput capacity from git and GitHub history. Builds contributor profiles (velocity, areas, merge time, trend), calculates team-wide metrics (parallelism factor, combined throughput), forecasts sprint capacity (pessimistic/expected/optimistic), identifies area coverage gaps (bus factor), and provides recommendations. Use this for sprint planning, capacity allocation, and identifying bottlenecks in the development process.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Analysis period in days (default 60)"),
    },
  },
  async ({ days }) => {
    try {
      const result = await getTeamCapacity(days ?? 60);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── PLANNING TOOLS ─────────────────────────────────────

server.registerTool(
  "plan_sprint",
  {
    title: "Sprint Planning Assistant",
    description:
      "AI-powered sprint planning that combines all intelligence modules: dependency graph (what's unblocked), team capacity (who can work on what), Monte Carlo simulation (confidence scoring), and backlog state (what's ready vs blocked). Returns a recommended sprint plan with: ordered items scored by priority/dependencies/capacity, stretch goals, deferred items with reasons, carry-over from in-progress work, confidence intervals, dependency warnings, and actionable recommendations. The 'killer feature' — use this for sprint planning, commitment decisions, and backlog prioritization.",
    inputSchema: {
      durationDays: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Sprint duration in days (default 14)"),
    },
  },
  async ({ durationDays }) => {
    try {
      const result = await planSprint(durationDays ?? 14);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "visualize_dependencies",
  {
    title: "Dependency Visualization",
    description:
      "Render the issue dependency graph as ASCII art and/or Mermaid diagram. Two modes: (1) Full graph — shows all connected issues, critical path highlighted, bottlenecks listed, dependency trees rendered. (2) Single issue — shows upstream blockers, downstream dependents, execution order, chain visualization. ASCII output is ready for terminal/monospace display. Mermaid output renders in GitHub, Notion, Obsidian. Color-coded by workflow state: green=Done, blue=Active, yellow=Review, gray=Ready, dashed=Backlog. Resolved dependencies shown as dotted lines.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Issue number for single-issue view. Omit for full graph."),
      format: z
        .enum(["both", "ascii", "mermaid"])
        .optional()
        .describe("Output format: 'both' (default), 'ascii' only, or 'mermaid' only"),
    },
  },
  async ({ issueNumber, format }) => {
    try {
      const result = await visualizeDependencies(issueNumber, format ?? "both");

      // Build output: combine ASCII and Mermaid with clear sections
      const parts: string[] = [];

      if (result.ascii) {
        parts.push(result.ascii);
      }

      if (result.mermaid) {
        if (parts.length > 0) parts.push("\n---\n");
        parts.push("MERMAID DIAGRAM (paste into GitHub/Notion/Obsidian):\n");
        parts.push(result.mermaid);
      }

      parts.push(`\n${result.summary}`);

      return {
        content: [{ type: "text" as const, text: parts.join("\n") }],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_project_dashboard",
  {
    title: "Project Health Dashboard",
    description:
      "Comprehensive project health report that synthesizes ALL intelligence modules into one view. Gathers board state, velocity, DORA metrics, workflow health, dependency graph, team capacity, and sprint simulation in parallel. Returns: overall health score (0-100) with status, individual health signals for 7 dimensions (velocity, DORA, workflow, dependencies, capacity, knowledge risk, learning), formatted markdown report with board snapshot, velocity table, dependency summary, team capacity breakdown, Monte Carlo histogram, and top 5 actionable recommendations prioritized by impact. Use this as the first call when starting a session or when asked 'how is the project doing?'",
  },
  async () => {
    try {
      const result = await getProjectDashboard();
      return {
        content: [{ type: "text" as const, text: result.report }],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── RESOURCES ──────────────────────────────────────────

server.registerResource(
  "board-overview",
  "pm://board/overview",
  {
    title: "Project Board Overview",
    description:
      "Current project board state with workflow distribution and health score",
    mimeType: "application/json",
  },
  async (uri) => {
    try {
      // Try cache first, fall back to live query
      const cache = await getBoardCache();
      if (cache) {
        return {
          contents: [{ uri: uri.href, text: JSON.stringify(cache, null, 2) }],
        };
      }
      const summary = await getLocalBoardSummary();
      return {
        contents: [{ uri: uri.href, text: JSON.stringify(summary, null, 2) }],
      };
    } catch (error) {
      return {
        contents: [
          {
            uri: uri.href,
            text: JSON.stringify({
              error: error instanceof Error ? error.message : String(error),
            }),
          },
        ],
      };
    }
  }
);

server.registerResource(
  "memory-decisions",
  "pm://memory/decisions",
  {
    title: "Recent Decisions",
    description:
      "Last 20 architectural and technical decisions from project memory",
    mimeType: "application/json",
  },
  async (uri) => {
    const decisions = await getDecisions(20);
    return {
      contents: [
        { uri: uri.href, text: JSON.stringify(decisions, null, 2) },
      ],
    };
  }
);

server.registerResource(
  "memory-outcomes",
  "pm://memory/outcomes",
  {
    title: "Recent Outcomes",
    description: "Last 20 work outcomes (merged, rework, reverted) from memory",
    mimeType: "application/json",
  },
  async (uri) => {
    const outcomes = await getOutcomes(20);
    return {
      contents: [
        { uri: uri.href, text: JSON.stringify(outcomes, null, 2) },
      ],
    };
  }
);

server.registerResource(
  "memory-insights",
  "pm://memory/insights",
  {
    title: "Memory Insights",
    description:
      "Analytics from project memory: rework rate, review patterns, area distribution",
    mimeType: "application/json",
  },
  async (uri) => {
    const insights = await getInsights();
    return {
      contents: [
        { uri: uri.href, text: JSON.stringify(insights, null, 2) },
      ],
    };
  }
);

server.registerResource(
  "event-stream",
  "pm://events/recent",
  {
    title: "Recent Events",
    description:
      "Last 50 events from the structured event stream (sessions, state changes, tool use)",
    mimeType: "application/json",
  },
  async (uri) => {
    const events = await getEvents(50);
    return {
      contents: [
        { uri: uri.href, text: JSON.stringify(events, null, 2) },
      ],
    };
  }
);

server.registerResource(
  "sprint-analytics",
  "pm://analytics/sprint",
  {
    title: "Sprint Analytics",
    description:
      "Current sprint analytics: cycle time, bottlenecks, flow efficiency, rework analysis",
    mimeType: "application/json",
  },
  async (uri) => {
    try {
      const analytics = await getSprintAnalytics(14);
      return {
        contents: [
          { uri: uri.href, text: JSON.stringify(analytics, null, 2) },
        ],
      };
    } catch (error) {
      return {
        contents: [
          {
            uri: uri.href,
            text: JSON.stringify({
              error: error instanceof Error ? error.message : String(error),
            }),
          },
        ],
      };
    }
  }
);

server.registerResource(
  "dora-metrics",
  "pm://analytics/dora",
  {
    title: "DORA Metrics",
    description:
      "DORA performance metrics: deployment frequency, lead time, change failure rate, MTTR",
    mimeType: "application/json",
  },
  async (uri) => {
    try {
      const metrics = await getDORAMetrics(30);
      return {
        contents: [
          { uri: uri.href, text: JSON.stringify(metrics, null, 2) },
        ],
      };
    } catch (error) {
      return {
        contents: [
          {
            uri: uri.href,
            text: JSON.stringify({
              error: error instanceof Error ? error.message : String(error),
            }),
          },
        ],
      };
    }
  }
);

// ─── OPERATIONAL INTELLIGENCE ────────────────────────────

server.registerTool(
  "suggest_next_issue",
  {
    title: "Suggest Next Issue",
    description:
      "Recommends the best issue to work on next based on priority, dependencies, " +
      "rework risk, estimated effort, and bottleneck impact. Scores and ranks all " +
      "unblocked Ready/Backlog issues. Returns top recommendation with alternatives.",
    inputSchema: {},
  },
  async () => {
    try {
      const suggestion = await suggestNextIssue();
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(suggestion, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "generate_standup",
  {
    title: "Generate Standup",
    description:
      "Auto-generates a daily standup report from project activity. Shows what was " +
      "completed, what's in progress, what's blocked, and what's coming up next. " +
      "Includes velocity metrics and flow efficiency.",
    inputSchema: {
      lookbackHours: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Hours to look back for activity (default: 24)"),
    },
  },
  async ({ lookbackHours }) => {
    try {
      const standup = await generateStandup(lookbackHours ?? 24);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(standup, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "generate_retro",
  {
    title: "Generate Retrospective",
    description:
      "Generates a data-driven sprint retrospective. Analyzes velocity trends, " +
      "rework patterns, bottlenecks, cycle times, and dependency health to produce " +
      "What Went Well / What Could Improve / Action Items. Includes patterns and " +
      "metrics evidence for each observation.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Sprint length in days to analyze (default: 14)"),
    },
  },
  async ({ days }) => {
    try {
      const retro = await generateRetro(days ?? 14);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(retro, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── EXPLANATORY INTELLIGENCE ────────────────────────────

server.registerTool(
  "explain_delay",
  {
    title: "Explain Delay",
    description:
      "Root cause analysis for why an issue is slow or stuck. Examines dependency " +
      "chains, rework cycles, bottleneck states, completion risk signals, and time " +
      "allocation (active vs waiting). Returns prioritized delay factors with evidence, " +
      "a chronological timeline, and actionable recommendations.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("GitHub issue number to analyze"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const explanation = await explainDelay(issueNumber);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(explanation, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "compare_estimates",
  {
    title: "Compare Estimates",
    description:
      "Compares predicted vs actual cycle times across completed issues. Measures " +
      "prediction accuracy at P50/P80/P95 levels, rework prediction hit rate, and " +
      "identifies systematic bias (optimistic/pessimistic/calibrated). Use to improve " +
      "future estimation accuracy and determine which confidence level to use for commitments.",
    inputSchema: {
      days: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Days to look back for completed issues (default: 30)"),
    },
  },
  async ({ days }) => {
    try {
      const calibration = await compareEstimates(days ?? 30);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(calibration, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── ANOMALY DETECTION ───────────────────────────────────

server.registerTool(
  "detect_patterns",
  {
    title: "Detect Patterns",
    description:
      "Cross-cutting anomaly detection that surfaces unusual patterns and early " +
      "warning signals across the project. Checks velocity drops, backlog growth, " +
      "rework trends, process violations (WIP limits, stale items), dependency " +
      "cycles and bottlenecks, capacity risks (bus factor, decelerating contributors), " +
      "and knowledge decay. Returns anomalies sorted by severity with evidence, " +
      "trend direction, affected issues, and suggested actions. The 'things you " +
      "should know about' early warning system.",
    inputSchema: {},
  },
  async () => {
    try {
      const report = await detectPatterns();
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(report, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── SMART TRIAGE ────────────────────────────────────────

server.registerTool(
  "triage_issue",
  {
    title: "Triage Issue",
    description:
      "One-call complete issue intelligence. Auto-classifies tier, type, area, " +
      "priority (with factor analysis), size estimate, risk assessment, rework " +
      "probability, similar past work, suggested assignees, relevant docs to load, " +
      "and spec readiness score. Use when picking up any new issue to get full " +
      "context in one call instead of querying multiple tools.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("GitHub issue number to triage"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const result = await triageIssue(issueNumber);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "analyze_pr_impact",
  {
    title: "Analyze PR Impact",
    description:
      "Blast radius analysis before merging a PR. Shows dependency impact (what " +
      "issues get unblocked), knowledge risk (bus factor for affected files), " +
      "coupling analysis (files that often change together), hotspot overlap, " +
      "and merge readiness score. Use before merging to understand systemic impact.",
    inputSchema: {
      prNumber: z
        .number()
        .int()
        .positive()
        .describe("Pull request number to analyze"),
    },
  },
  async ({ prNumber }) => {
    try {
      const result = await analyzePRImpact(prNumber);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "decompose_issue",
  {
    title: "Decompose Issue",
    description:
      "Break a large issue or epic into smaller, dependency-ordered subtasks. " +
      "Generates subtask suggestions with titles, types, acceptance criteria, " +
      "size estimates, risk levels, and dependency relationships. Calculates " +
      "critical path, parallelization speedup ratio, and execution order phases. " +
      "Use for sprint planning or when an issue feels too large to start.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("GitHub issue number to decompose"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const result = await decomposeIssue(issueNumber);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "simulate_dependency_change",
  {
    title: "Simulate Dependency Change",
    description:
      "What-if analysis: 'What happens if issue #X slips by N days?' " +
      "Models cascading delay through the dependency graph, shows which issues " +
      "are impacted and by how much, quantifies total schedule slip, critical " +
      "path impact, and suggests mitigations with alternative scenarios. " +
      "Set removeIssue=true to model removing an issue from the dependency chain entirely.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to model slipping"),
      slipDays: z
        .number()
        .positive()
        .describe("Number of days the issue would slip"),
      removeIssue: z
        .boolean()
        .optional()
        .default(false)
        .describe("If true, model removing this issue from the dependency chain"),
    },
  },
  async ({ issueNumber, slipDays, removeIssue }) => {
    try {
      const result = await simulateDependencyChange(
        issueNumber,
        slipDays,
        removeIssue
      );
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "generate_release_notes",
  {
    title: "Generate Release Notes",
    description:
      "Build structured release notes from merged PRs and closed issues. " +
      "Groups changes by area, classifies by type (feature/fix/breaking/etc), " +
      "generates stakeholder summary, technical notes, and full markdown. " +
      "Defaults to last 7 days if no date range specified.",
    inputSchema: {
      since: z
        .string()
        .optional()
        .describe("Start date (YYYY-MM-DD). Defaults to 7 days ago"),
      until: z
        .string()
        .optional()
        .describe("End date (YYYY-MM-DD). Defaults to today"),
      version: z
        .string()
        .optional()
        .describe("Version label for the release. Defaults to the end date"),
    },
  },
  async ({ since, until, version }) => {
    try {
      const result = await generateReleaseNotes(since, until, version);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "optimize_session",
  {
    title: "Optimize Session",
    description:
      "Context-aware session planning. Analyzes current project state — active " +
      "issues, review queue, rework pending, dependency bottlenecks, stale items, " +
      "anomalies — and recommends the most impactful work for this session. " +
      "Returns a prioritized plan with time estimates, quick wins, and deferrals. " +
      "Use at the start of every coding session for maximum impact.",
    inputSchema: {
      availableMinutes: z
        .number()
        .int()
        .positive()
        .optional()
        .default(120)
        .describe("Available minutes for this session. Default 120"),
      focusArea: z
        .string()
        .optional()
        .describe("Optional: focus on a specific area (frontend, backend, etc)"),
    },
  },
  async ({ availableMinutes, focusArea }) => {
    try {
      const result = await optimizeSession(availableMinutes, focusArea);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "review_pr",
  {
    title: "Review PR",
    description:
      "Structured PR analysis: file classification, scope check, acceptance " +
      "criteria verification, risk assessment (secrets, knowledge risk, large files), " +
      "quality signals (tests, types, config changes), and verdict recommendation. " +
      "Returns approve/request_changes/needs_discussion with specific blockers and suggestions.",
    inputSchema: {
      prNumber: z
        .number()
        .int()
        .positive()
        .describe("Pull request number to review"),
    },
  },
  async ({ prNumber }) => {
    try {
      const result = await reviewPR(prNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "auto_label",
  {
    title: "Auto Label",
    description:
      "Automatic issue classification from content analysis. Suggests type " +
      "(bug/feature/spike/epic/chore), area (frontend/backend/contracts/infra), " +
      "priority, risk level, and spec readiness based on title and body keyword matching. " +
      "Returns suggestions with confidence scores — labels are NOT applied automatically.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to classify"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const result = await autoLabel(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_session_history",
  {
    title: "Get Session History",
    description:
      "Cross-session event history for an issue. Shows workflow transitions, " +
      "decisions made, outcomes recorded, session gaps (>1 day), and approximate " +
      "session count. Use to understand what happened with an issue over time.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to get history for"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const result = await getSessionHistory(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "recover_context",
  {
    title: "Recover Context",
    description:
      "Full context recovery to resume work on an issue. Loads: current state, " +
      "previous plans, linked PR status, review feedback, decisions, event timeline, " +
      "dependencies, predictions, and issue comments. Returns a resumption guide " +
      "with detected mode (START/CONTINUE/REWORK/etc), next steps, warnings, " +
      "and context files to load. The 'pick up where you left off' tool.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("Issue number to recover context for"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const result = await recoverContext(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "bulk_triage",
  {
    title: "Bulk Triage",
    description:
      "Triage all untriaged issues in one call. Finds open issues missing type: " +
      "or area: labels and suggests classifications for each. Labels are suggestions " +
      "only — not applied automatically. Use for backlog grooming and project cleanup.",
    inputSchema: {
      maxIssues: z
        .number()
        .int()
        .positive()
        .optional()
        .default(20)
        .describe("Maximum issues to process. Default 20"),
    },
  },
  async ({ maxIssues }) => {
    try {
      const result = await bulkTriage(maxIssues);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "bulk_move",
  {
    title: "Bulk Move",
    description:
      "Move multiple issues between workflow states in one call. Supports dry " +
      "run mode to preview changes. Use for sprint transitions (Ready → Active), " +
      "cleanup (stale → Backlog), or batch state corrections.",
    inputSchema: {
      issueNumbers: z
        .array(z.number().int().positive())
        .describe("Array of issue numbers to move"),
      targetState: z
        .string()
        .describe("Target workflow state (Backlog, Ready, Active, Review, Rework, Done)"),
      dryRun: z
        .boolean()
        .optional()
        .default(false)
        .describe("If true, preview changes without applying them"),
    },
  },
  async ({ issueNumbers, targetState, dryRun }) => {
    try {
      const result = await bulkMove(issueNumbers, targetState, dryRun);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

server.registerTool(
  "get_risk_radar",
  {
    title: "Get Risk Radar",
    description:
      "Comprehensive risk assessment synthesizing ALL intelligence signals: " +
      "delivery velocity, quality (rework rate, DORA CFR), knowledge (bus factor, " +
      "critical files), process (stale items, WIP violations), dependencies " +
      "(cycles, bottlenecks, orphaned), and capacity (deceleration). Returns " +
      "overall risk score (0-100), prioritized risk list with trend arrows, " +
      "health indicators per category, and actionable mitigations. " +
      "The executive risk dashboard in one call.",
    inputSchema: {},
  },
  async () => {
    try {
      const result = await getRiskRadar();
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// ─── MAIN ───────────────────────────────────────────────

const ALL_TOOLS = [
  "get_issue_status", "get_board_summary", "move_issue", "get_velocity",
  "record_decision", "record_outcome", "get_memory_insights", "get_event_stream",
  "get_sprint_analytics", "suggest_approach", "check_readiness", "get_history_insights",
  "predict_completion", "predict_rework", "get_dora_metrics", "get_knowledge_risk",
  "record_review_outcome", "get_review_calibration", "check_decision_decay",
  "simulate_sprint", "forecast_backlog",
  "detect_scope_creep", "get_context_efficiency", "get_workflow_health",
  "analyze_dependency_graph", "get_issue_dependencies", "get_team_capacity",
  "plan_sprint",
  "visualize_dependencies",
  "get_project_dashboard",
  "suggest_next_issue", "generate_standup", "generate_retro",
  "explain_delay", "compare_estimates",
  "detect_patterns",
  "triage_issue", "analyze_pr_impact", "decompose_issue",
  "simulate_dependency_change", "generate_release_notes", "optimize_session",
  "review_pr", "auto_label",
  "get_session_history", "recover_context",
  "bulk_triage", "bulk_move",
  "get_risk_radar",
];

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("PM Intelligence MCP Server v0.13.0 running on stdio");
  console.error(`Tools: ${ALL_TOOLS.join(", ")}`);
}

process.on("SIGINT", async () => {
  console.error("Shutting down PM Intelligence MCP server...");
  await server.close();
  process.exit(0);
});

main().catch((error) => {
  console.error("Fatal error in PM Intelligence MCP server:", error);
  process.exit(1);
});
