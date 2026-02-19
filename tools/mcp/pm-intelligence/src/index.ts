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
 *
 * Resources:
 *   - pm://board/overview: Board summary (same as tool, but as resource)
 *   - pm://memory/decisions: Recent decisions
 *   - pm://memory/outcomes: Recent outcomes
 *   - pm://memory/insights: Memory analytics
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { WORKFLOW_STATES } from "./config.js";
import {
  getIssueStatus,
  getBoardSummary,
  moveIssue,
  getVelocity,
} from "./github.js";
import {
  getDecisions,
  getOutcomes,
  getBoardCache,
  recordDecision,
  recordOutcome,
  updateBoardCache,
  getInsights,
} from "./memory.js";

const server = new McpServer({
  name: "pm-intelligence",
  version: "0.5.0",
});

// ─── TOOLS ──────────────────────────────────────────────

server.registerTool(
  "get_issue_status",
  {
    title: "Get Issue Status",
    description:
      "Get the current workflow state, priority, area, labels, and assignees for a GitHub issue. Returns the issue's position on the project board.",
    inputSchema: {
      issueNumber: z
        .number()
        .int()
        .positive()
        .describe("GitHub issue number"),
    },
  },
  async ({ issueNumber }) => {
    try {
      const status = await getIssueStatus(issueNumber);
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(status, null, 2) },
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
      "Get a comprehensive project board summary: issue counts by workflow state, priority distribution, active/review/rework items, stale item detection, and a health score (0-100). Use this to understand the current state of the project.",
  },
  async () => {
    try {
      const summary = await getBoardSummary();

      // Also update the board cache for SessionStart hook
      await updateBoardCache({
        active: summary.byWorkflow["Active"] || 0,
        review: summary.byWorkflow["Review"] || 0,
        rework: summary.byWorkflow["Rework"] || 0,
        done: summary.byWorkflow["Done"] || 0,
        backlog: summary.byWorkflow["Backlog"] || 0,
        ready: summary.byWorkflow["Ready"] || 0,
      });

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
      "Move a GitHub issue to a new workflow state on the project board. Valid states: Backlog, Ready, Active, Review, Rework, Done. NOTE: Use the bash script project-move.sh for the Review transition (it includes pre-review test gates).",
    inputSchema: {
      issueNumber: z.number().int().positive().describe("GitHub issue number"),
      targetState: z
        .enum(WORKFLOW_STATES)
        .describe("Target workflow state"),
    },
  },
  async ({ issueNumber, targetState }) => {
    try {
      const result = await moveIssue(issueNumber, targetState);
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
      "Record a work outcome (merged, rework, reverted, abandoned) to persistent JSONL memory. Automatically called by project-move.sh on Done transitions, but can be called directly for manual recording with richer detail.",
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
      const summary = await getBoardSummary();
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

// ─── MAIN ───────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("PM Intelligence MCP Server v0.5.0 running on stdio");
  console.error(
    `Tools: ${["get_issue_status", "get_board_summary", "move_issue", "get_velocity", "record_decision", "record_outcome", "get_memory_insights"].join(", ")}`
  );
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
