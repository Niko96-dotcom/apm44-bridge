# Stop Policy

Stop the loop when any condition is true:

- No accepted P0 or P1 findings remain.
- Two consecutive review waves find no new accepted high-confidence P0 or P1 findings.
- Remaining P2 findings are below threshold, low-value, or too broad.
- Max iterations is reached.
- Max attempts for a finding is reached.
- `.deslop/stop` exists.
- The tree is unexpectedly dirty and the command was not run with an explicit dirty allowance.
- Verification fails repeatedly or verifier perspectives deadlock.
- A finding is marked `needs_human`.
- A proposed fix requires broad risky surgery.

The arbiter should be conservative: reject weak findings, mark human-needed work honestly, and stop rather than running indefinitely.
