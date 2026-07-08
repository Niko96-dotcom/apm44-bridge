---
description: Run the bounded Ultimate De-Slop review, fix, check, verify loop in the current repository.
argument-hint: "[--review-only] [--max-iterations N] [--priority P0,P1[,P2]] [--allow-dirty]"
tools:
  bash: true
  read: true
  glob: true
  grep: true
---

<objective>
Run Ultimate De-Slop in the current repository through the installed local harness.
</objective>

<context>
Arguments: $ARGUMENTS
</context>

<process>
Find the installed skill directory in this order:

1. `.opencode/skills/ultimate-de-slop`
2. `.opencode/skill/ultimate-de-slop`
3. `$HOME/.config/opencode/skills/ultimate-de-slop`
4. `$HOME/.config/opencode/skill/ultimate-de-slop`
5. `$HOME/.agents/skills/ultimate-de-slop`
6. `$HOME/.claude/skills/ultimate-de-slop`

If `--review-only` is present, run:

```sh
DESLOP_HARNESS=opencode "$SKILL_DIR/scripts/deslop-review.sh"
```

Otherwise run the bounded loop. Default to `--max-iterations 5 --priority P0,P1` when those flags are not supplied:

```sh
DESLOP_HARNESS=opencode "$SKILL_DIR/scripts/deslop-loop.sh" --max-iterations 5 --priority P0,P1
```

Forward any explicit `$ARGUMENTS` flags that belong to the harness. Report the `.deslop/` run directory, status, and next command.
</process>
