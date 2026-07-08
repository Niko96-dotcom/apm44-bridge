# Severity Rubric

## P0

Correctness, security, data loss, build break, test break, or serious production breakage.

Default confidence threshold: `0.70`.

Examples:

- A code path can delete or corrupt user data.
- A security boundary is bypassable.
- The default build or test command is broken.

## P1

Serious structural issue already hurting maintainability or correctness velocity.

Default confidence threshold: `0.75`.

Examples:

- A busy flow contains repeated ad-hoc conditionals that make correctness fragile.
- Ownership boundaries are mixed so fixes require edits across unrelated layers.
- A giant file is already blocking safe change.

## P2

Bounded cleanup with clear payoff and low or regression-controlled risk.

Default confidence threshold: `0.85`.

Examples:

- A duplicated adapter can be collapsed behind an existing canonical helper.
- A medium-sized flow can be simplified with a small extraction and tests.

## P3

Style, preference, naming taste, formatting, speculative cleanup, or broad rewrite ideas.

P3 is rejected by default and must not fuel the loop.
