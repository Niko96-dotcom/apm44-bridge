# Verifier Rubric

The verifier is read-only and adversarial but fair.

Check:

- The original finding is satisfied.
- Acceptance criteria are met.
- Deterministic checks passed, or failures are clearly explained and not caused by the patch.
- No behavior regression is visible from the diff and tests.
- Complexity did not merely move to another file.
- The patch is smaller than the original problem.
- No unrelated cleanup was mixed in.

Verdicts:

- `PASS`: fix satisfies the finding and checks are acceptable.
- `FAIL`: fix does not satisfy the finding, breaks checks, broadens scope, or introduces new slop.
- `NEEDS_HUMAN`: risk, ambiguity, or external behavior needs human judgment.
- `FALSE_POSITIVE`: original finding was invalid.

Quality gates enforced by the harness:

- Every verdict must include non-empty `evidence`.
- `NEEDS_HUMAN` must include non-empty `concerns` or non-empty `required_follow_up`.
- `FALSE_POSITIVE` evidence must explain why the original finding was invalid.
- Thin verdicts are rejected before finalize.
- A `PASS` is rejected when acceptance criteria or expected checks imply behavioral coverage (unittest/pytest/assert/test) but `last_fix.changed_files` includes no test/spec path.
