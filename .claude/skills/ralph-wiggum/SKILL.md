---
name: ralph-wiggum
description: The Ralph Wiggum technique for iterative AI development loops. Use when building greenfield projects, when user says "ralph it", "ralph loop", or wants autonomous iterative development with eventual consistency.
---

# Ralph Wiggum Technique

Ralph is a development methodology for autonomous, iterative AI loops. Named after Ralph Wiggum from The Simpsons - deterministically bad in an undeterministic world, but eventually consistent.

## Activation Triggers
- "ralph it", "ralph this", "ralph loop"
- "autonomous loop", "iterative loop"
- "run it until done", "keep going until complete"
- "greenfield with ralph"
- When user wants unattended iterative development

## Core Philosophy

1. **Iteration > Perfection** - Don't aim for perfect on first try. Let the loop refine.
2. **One task per loop** - Only ONE thing per iteration. This is critical.
3. **Failures are data** - Each failure tunes the prompt, like tuning a guitar.
4. **Operator skill matters** - Success depends on writing good prompts.
5. **Trust eventual consistency** - Ralph will test you. Keep faith.

## The Technique

```
while :; do cat PROMPT.md | claude ; done
```

The loop happens inside Claude Code via the stop hook. Each iteration:
1. Works on ONE task from fix_plan.md
2. Tries to exit
3. Stop hook blocks exit, feeds SAME prompt back
4. Previous work persists in files and git
5. Repeat until completion

## Critical Rules

### 1. One Task Per Loop
Pick the MOST IMPORTANT single item from fix_plan.md. Only one. Let the LLM reason about priority.

### 2. Minimize Context Window Usage
- Use subagents for expensive operations (file search, code analysis)
- Main context = scheduler only
- Don't allocate search results to primary context

### 3. Always Search Before Assuming
```
Before making changes search codebase (don't assume not implemented) using subagents.
```
Ripgrep is non-deterministic. Never assume code doesn't exist without searching.

### 4. No Placeholders
```
DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. FULL IMPLEMENTATIONS ONLY.
```

### 5. Maintain fix_plan.md
- Living TODO list sorted by priority
- Update after every discovery
- Remove completed items
- Document bugs found (even unrelated ones)

### 6. Self-Improvement
- Update AGENT.md with learnings about build/test commands
- Capture WHY in test documentation
- Loop learnings back into the system

### 7. Git Discipline
- Commit when tests pass
- Tag releases (increment patch: 0.0.1, 0.0.2...)
- Push after commits

## Prompt Structure

### Building Prompt
```markdown
1. Study specs/* and fix_plan.md
2. Choose the most important ONE thing from fix_plan.md
3. Before changes, search codebase using subagents (don't assume not implemented)
4. Implement using subagents (up to N parallel, but only 1 for build/test)
5. Run tests for that unit of code
6. If tests pass:
   a. Spawn code-simplifier agent on modified files
   b. If UI/frontend work was done:
      - Run /i-normalize to align with design system
      - Run /i-polish for final quality pass
      - Run /i-audit for a11y/perf/responsive check
   c. Run tests again to verify changes didn't break anything
   d. Update fix_plan.md
   e. git add -A, git commit, git push
7. If tests fail: debug, fix, repeat
8. Document learnings in AGENT.md
9. Update fix_plan.md with any bugs discovered

CRITICAL: NO PLACEHOLDER IMPLEMENTATIONS. FULL IMPLEMENTATIONS ONLY.
```

### Planning Prompt
```markdown
1. Study specs/* and existing fix_plan.md
2. Use subagents to analyze src/* against specifications
3. Create/update fix_plan.md as prioritized bullet list
4. Search for TODO, minimal implementations, placeholders
5. Keep fix_plan.md up to date with complete/incomplete status
```

## Project Structure

```
project/
├── specs/           # Specifications (one per file)
├── src/             # Source code
├── fix_plan.md      # Living TODO, prioritized
├── AGENT.md         # Build/test instructions, learnings
└── .claude/
    └── ralph-loop.local.md  # Loop state (auto-managed)
```

## Specifications

Before building, have a long conversation about requirements. Then:
```
Write specifications, one per file, in the specs/ folder
```

Specs are allocated to context every loop. They ARE the source of truth.

## Back Pressure

Tests and builds are back pressure. Fast wheel turning matters:
- Type systems provide back pressure (Rust = slow but correct)
- Wire in linters, static analyzers, security scanners
- Dynamically typed languages NEED type checkers (pyrefly, dialyzer)

## When to Use Ralph

**Good for:**
- Greenfield projects
- Well-defined tasks with clear specs
- Tasks with automatic verification (tests)
- Projects you can walk away from overnight

**Not good for:**
- Existing codebases (proceed with extreme caution)
- Tasks requiring human judgment
- Unclear success criteria
- Production debugging

## Escape Hatches

Always set --max-iterations. When stuck:
- Document what's blocking in fix_plan.md
- List what was attempted
- Sometimes: git reset --hard and restart

## Real Results

- 6 repos shipped overnight (YC hackathon)
- $50k contract for $297 in API costs
- CURSED programming language (3 months, no training data)

## Starting a Ralph Loop

```bash
/ralph-loop "Your task. Follow fix_plan.md, pick ONE item, implement fully, commit on green." --completion-promise "DONE" --max-iterations 50
```

Or for planning:
```bash
/ralph-loop "Study specs/* and src/*, create fix_plan.md with prioritized items" --max-iterations 10
```

## Remember

> "Any problem created by AI can be resolved through a different series of prompts"

When Ralph goes off the rails, don't blame the tools. Tune the prompt. Add signs. Get a new Ralph.
