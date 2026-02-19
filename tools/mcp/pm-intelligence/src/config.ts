/**
 * PM configuration — values replaced by install.sh placeholder system.
 *
 * These match the bash pm.config.sh variables. When install.sh processes
 * this file, it replaces {{PLACEHOLDERS}} with real project values.
 */

export const PM_CONFIG = {
  owner: "{{OWNER}}",
  projectNumber: Number("{{PROJECT_NUMBER}}") || 0,
  projectId: "{{PROJECT_ID}}",

  fields: {
    workflow: "{{FIELD_WORKFLOW}}",
    priority: "{{FIELD_PRIORITY}}",
    area: "{{FIELD_AREA}}",
    issueType: "{{FIELD_ISSUE_TYPE}}",
    risk: "{{FIELD_RISK}}",
    estimate: "{{FIELD_ESTIMATE}}",
  },

  workflow: {
    backlog: "{{OPT_WF_BACKLOG}}",
    ready: "{{OPT_WF_READY}}",
    active: "{{OPT_WF_ACTIVE}}",
    review: "{{OPT_WF_REVIEW}}",
    rework: "{{OPT_WF_REWORK}}",
    done: "{{OPT_WF_DONE}}",
  },

  priority: {
    critical: "{{OPT_PRI_CRITICAL}}",
    high: "{{OPT_PRI_HIGH}}",
    normal: "{{OPT_PRI_NORMAL}}",
  },

  type: {
    bug: "{{OPT_TYPE_BUG}}",
    feature: "{{OPT_TYPE_FEATURE}}",
    spike: "{{OPT_TYPE_SPIKE}}",
    epic: "{{OPT_TYPE_EPIC}}",
    chore: "{{OPT_TYPE_CHORE}}",
  },
} as const;

/** Map state names to option IDs */
export const WORKFLOW_MAP: Record<string, string> = {
  Backlog: PM_CONFIG.workflow.backlog,
  Ready: PM_CONFIG.workflow.ready,
  Active: PM_CONFIG.workflow.active,
  Review: PM_CONFIG.workflow.review,
  Rework: PM_CONFIG.workflow.rework,
  Done: PM_CONFIG.workflow.done,
};

/** Valid workflow states */
export const WORKFLOW_STATES = [
  "Backlog",
  "Ready",
  "Active",
  "Review",
  "Rework",
  "Done",
] as const;

export type WorkflowState = (typeof WORKFLOW_STATES)[number];
