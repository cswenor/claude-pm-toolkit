# Claude Instruction Architecture

This document describes the architecture of Claude instructions in projects managed by the claude-pm-toolkit.

---

## Architecture Overview

```
                              INSTRUCTION LAYERS
+-----------------------------------------------------------------------------+
|                                                                             |
|  CORE LAYER (CLAUDE.md)                                                     |
|  ├── Stop checks (quick reference checklists)                               |
|  ├── Critical policies (NO FALLBACKS, PREFER MCP, etc.)                     |
|  ├── Context recovery pointers (links to PM_PLAYBOOK, etc.)                 |
|  ├── AI behavioral constraints (what states allow coding)                   |
|  ├── Project overview (stack, structure, commands)                          |
|  └── Conventions (commits, testing, security)                               |
|                                                                             |
+-----------------------------------------------------------------------------+
                                     │
                                     │ references
                                     ▼
+-----------------------------------------------------------------------------+
|                                                                             |
|  REFERENCE LAYER (docs/)                                                    |
|  ├── PM_PLAYBOOK.md (CANONICAL for all PM processes)                        |
|  │   ├── Workflow state definitions (Backlog, Ready, Active, Review,        |
|  │   │   Rework, Done)                                                      |
|  │   ├── Workflow transitions and triggers                                  |
|  │   ├── Tier classification (full tables)                                  |
|  │   ├── GitHub Project field IDs                                           |
|  │   └── Issue documentation policy                                         |
|  │                                                                          |
|  ├── REVIEW_GUIDE.md (review standards and calibration tools)               |
|  │   └── PR review format, risk flags, toolkit calibration workflow         |
|  │                                                                          |
|  └── PM_PROJECT_CONFIG.md (project configuration reference)                 |
|                                                                             |
+-----------------------------------------------------------------------------+
                                     │
                                     │ skill-specific logic only
                                     ▼
+-----------------------------------------------------------------------------+
|                                                                             |
|  SKILLS LAYER (.claude/skills/)                                             |
|  ├── /issue - Issue creation & execution                                    |
|  │   ├── Mode detection, worktree handling, interview flow                  |
|  │   └── Swarm delegation (Planner/Developer agents via Task tool)          |
|  ├── /pm-review - PM Reviewer persona                                       |
|  ├── /weekly - Weekly report analysis                                       |
|  ├── /start - Session startup                                               |
|  └── /audit - PM process auditing                                           |
|                                                                             |
|  Skills reference PM_PLAYBOOK.md for workflow rules.                        |
|  Skills contain ONLY skill-specific logic (mode detection, UI flows).       |
|                                                                             |
+-----------------------------------------------------------------------------+
```

---

## Source of Truth Table

| Content                    | Canonical Source          | Notes                                                  |
| -------------------------- | ------------------------ | ------------------------------------------------------ |
| Workflow state definitions | `docs/PM_PLAYBOOK.md`    | 6 states: Backlog, Ready, Active, Review, Rework, Done |
| Workflow transitions       | `docs/PM_PLAYBOOK.md`    | When and how issues move between states                |
| Tier classification        | `docs/PM_PLAYBOOK.md`    | Full tables with prefixes and requirements             |
| GitHub Project field IDs   | `docs/PM_PLAYBOOK.md`    | All option IDs for workflow, priority, area, etc.      |
| Stop checks                | `CLAUDE.md`              | Quick-reference checklists                             |
| AI behavioral constraints  | `CLAUDE.md`              | What AI can/cannot do in each state                    |
| Critical policies          | `CLAUDE.md`              | NO FALLBACKS, PREFER MCP, etc.                         |
| PR review standards        | `docs/REVIEW_GUIDE.md`   | Review format, risk flags, calibration tools           |
| Project configuration      | `docs/PM_PROJECT_CONFIG.md` | Config file format, field mappings                  |
| Skill-specific logic       | Each skill's `SKILL.md`  | Mode detection, interview flows, UI                    |
| Swarm delegation           | `/issue` SKILL.md        | Agent roles, prompt templates, phase gates, authority  |

---

## Key Principles

### 1. Single Source of Truth

Each piece of information has exactly ONE canonical location. Other files may reference it but not duplicate it.

**Example:** Workflow states are defined in PM_PLAYBOOK.md. CLAUDE.md may summarize AI behavioral constraints per state, but doesn't redefine the states themselves.

### 2. Reference, Don't Duplicate

When content exists in a canonical source, other files should link to it:

```markdown
<!-- GOOD: Reference -->

See `docs/PM_PLAYBOOK.md` for workflow state definitions.

<!-- BAD: Duplication - don't recreate tables from PM_PLAYBOOK -->
```

### 3. Behavioral Constraints vs. Definitions

- **Definitions** (what states exist, what transitions are valid) belong in PM_PLAYBOOK.md
- **Behavioral constraints** (what AI can/cannot do) belong in CLAUDE.md

### 4. Skills Are Self-Contained for Skill Logic

Skills define their own:

- Mode detection rules
- Interview flows
- UI interactions
- Guardrails specific to the skill

Skills do NOT define:

- Workflow state meanings
- Tier classification rules
- General PM processes

---

## Verification Commands

Run these to check for architecture violations:

```bash
# Workflow state tables should only be in PM_PLAYBOOK
grep -rn "| State.*| Meaning" --include="*.md" docs/ CLAUDE.md | grep -v PM_PLAYBOOK

# Transition tables should only be in PM_PLAYBOOK
grep -rn "| Transition.*| Trigger" --include="*.md" docs/ CLAUDE.md | grep -v PM_PLAYBOOK

# Verify Rework state is referenced in key files
grep -l "Rework" CLAUDE.md docs/PM_PLAYBOOK.md docs/REVIEW_GUIDE.md

# Check for duplicated source-of-truth content in skills
grep -rn "| State.*| Meaning" --include="*.md" .claude/skills/
```

---

## Adding New Skills

1. **Create skill directory:** `.claude/skills/<skill-name>/`
2. **Create SKILL.md** with frontmatter and implementation
3. **Add to skills index:** `.claude/skills/README.md`
4. **Reference PM_PLAYBOOK.md** for any workflow rules (don't duplicate)
5. **Keep skill logic in skill file** — mode detection, UI, guardrails

---

## Maintenance

### When Updating Workflow Rules

1. Update `docs/PM_PLAYBOOK.md` (the canonical source)
2. Verify CLAUDE.md behavioral constraints still align
3. Verify skills reference the correct state names
4. Run verification commands

### When Adding New Policies

1. Determine the appropriate layer:
   - Critical policy -> CLAUDE.md
   - PM process detail -> PM_PLAYBOOK.md
   - Review standards -> REVIEW_GUIDE.md
   - Skill-specific logic -> skill's SKILL.md
2. Add to ONE location only
3. Update this architecture doc if adding new categories

### When Installing into a Target Repository

The installer (`install.sh`) injects toolkit sections into the target's CLAUDE.md and Makefile using sentinel markers (`<!-- claude-pm-toolkit:start/end -->` and `# claude-pm-toolkit:start/end`). The instruction architecture still applies — the injected content references `docs/PM_PLAYBOOK.md` and other canonical sources rather than duplicating them.
