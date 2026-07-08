# Reviewer Rubric

Perform a strict structural review. Look for changes that make the codebase materially easier to reason about, safer to change, or less likely to hide defects.

Prefer findings about:

- Structural simplification.
- Deleting complexity instead of moving it.
- Giant file sprawl that is already causing unsafe edits.
- Ad-hoc conditionals inside busy flows.
- Type and boundary cleanliness.
- Canonical layer ownership.
- Duplicate logic with real drift risk.
- Invariants that are implicit, repeated, or unenforced.

Reject:

- Low-value style nits.
- Thin wrappers that only rename existing behavior.
- Magical generic abstractions.
- Speculative rewrites.
- Vague "could be cleaner" comments.
- Findings without concrete evidence.

Every finding must include concrete files and symbols or line ranges when available, a bounded proposed fix, acceptance criteria, expected checks, risk, effort, and confidence. Return at most 5 findings per reviewer.
