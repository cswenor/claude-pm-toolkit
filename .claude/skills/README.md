# Claude Skills Index

This document indexes all Claude skills in the PM toolkit and defines source-of-truth rules.

---

## Available Skills

| Skill        | Purpose                                                     | Invocation                           |
| ------------ | ----------------------------------------------------------- | ------------------------------------ |
| `/issue`     | Create new issues (PM interview) or work on existing issues | `/issue` or `/issue <number>`        |
| `/pm-review` | PM Reviewer persona for analyzing issues/PRs                | `/pm-review`                         |
| `/weekly`    | Generate AI narrative from weekly JSON snapshots            | `/weekly` or `/weekly --from <date>` |
| `/start`     | Start session with AI-powered planning and risk briefing    | `/start` or `/start <minutes>`       |
| `/simplify`  | Review changed code for reuse, quality, and efficiency      | `/simplify`                          |

---

## Source of Truth Table

These rules are **enforceable via grep**. Violations indicate duplication that should be removed.

| Content                                                                   | Canonical Source          | Rule                                        |
| ------------------------------------------------------------------------- | ------------------------- | ------------------------------------------- |
| Workflow state definitions (Backlog, Ready, Active, Review, Rework, Done) | `docs/PM_PLAYBOOK.md`     | Tables defining states ONLY in PM_PLAYBOOK  |
| Workflow transition rules                                                 | `docs/PM_PLAYBOOK.md`     | Transition tables ONLY in PM_PLAYBOOK       |
| Tier classification tables                                                | `docs/PM_PLAYBOOK.md`     | Full tier tables ONLY in PM_PLAYBOOK        |
| Stop checks                                                               | `claude-md-sections.md`   | Stop check checklists ONLY in template      |
| Agent operating constraints                                               | `claude-md-sections.md`   | Behavioral rules ONLY in template           |
| No-fallback policy                                                        | `claude-md-sections.md`   | Policy definition ONLY in template          |
| Discovered work policy                                                    | `claude-md-sections.md`   | Policy definition ONLY in template          |
| Skill-specific logic                                                      | Each skill's `SKILL.md`   | Mode detection, appendices in skill files   |
| Design principles                                                         | `/issue` SKILL.md         | Principles table ONLY in issue skill        |
| MCP tool reference tables                                                 | `claude-md-sections.md`   | Tool usage tables ONLY in template          |

---

## Three-Layer Instruction Architecture

| Layer         | Content                                          | Files                                    |
| ------------- | ------------------------------------------------ | ---------------------------------------- |
| **CORE**      | Stop checks, critical policies, AI constraints   | `claude-md-sections.md` → target CLAUDE.md |
| **REFERENCE** | PM processes, field IDs, workflow definitions     | `docs/PM_PLAYBOOK.md`                    |
| **SKILLS**    | Skill-specific logic, mode detection, guardrails  | `.claude/skills/*/SKILL.md`              |

**Single Source of Truth Principle:**
- Workflow definitions → **PM_PLAYBOOK.md ONLY**
- Workflow transitions → **PM_PLAYBOOK.md ONLY**
- Tier classification → **PM_PLAYBOOK.md ONLY**
- AI behavioral constraints → **claude-md-sections.md ONLY**
- Critical policies → **claude-md-sections.md ONLY**

---

## Consistency Rules

### Hard Rules (lintable)

1. **Workflow state tables**: Only `docs/PM_PLAYBOOK.md` may contain tables defining workflow states with columns like `| State | Meaning | AI Behavior |`
2. **Tier classification tables**: Only `docs/PM_PLAYBOOK.md` may contain the full tier classification table with `| PR Title Prefix | Issue Required? |`
3. **Stop checks**: Only `claude-md-sections.md` may define the stop check checklists
4. **Design principles**: Only the `/issue` SKILL.md may define the design principles table

### Soft Rules

1. **Cross-links are allowed** - Skills and CLAUDE.md may reference PM_PLAYBOOK.md for details
2. **Behavioral constraints allowed** - CLAUDE.md may summarize AI behavioral rules (e.g., "coding only in Active")
3. **When duplicated text differs, PM_PLAYBOOK.md wins** - It is the canonical source for PM processes

---

## Verification Commands

```bash
# Check for workflow state table definitions outside PM_PLAYBOOK
grep -rn "| State.*| Meaning" --include="*.md" . | grep -v PM_PLAYBOOK

# Check for transition tables outside PM_PLAYBOOK
grep -rn "| Transition.*| Trigger" --include="*.md" . | grep -v PM_PLAYBOOK

# Check for stop checks outside claude-md-sections
grep -rn "### Before Starting Work" --include="*.md" . | grep -v claude-md-sections

# Verify Rework state is referenced in key files
grep -l "Rework" claude-md-sections.md docs/PM_PLAYBOOK.md .claude/skills/issue/SKILL.md
```

---

## Adding a New Skill

1. Create directory: `.claude/skills/<skill-name>/`
2. Create `SKILL.md` with skill definition (frontmatter: name, description, argument-hint, allowed-tools)
3. Add entry to the Available Skills table above
4. Reference PM_PLAYBOOK.md for workflow rules (don't duplicate)
5. Keep skill-specific logic in the skill file only
6. If the skill has sub-playbooks, create `.claude/skills/<skill-name>/sub-playbooks/`
7. If the skill has appendices, create `.claude/skills/<skill-name>/appendices/`
