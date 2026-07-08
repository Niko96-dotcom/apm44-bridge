# Examples

## Finding

```json
{
  "id": "DSL-000001",
  "title": "Request validation is duplicated across three entrypoints",
  "severity": "P1",
  "confidence": 0.88,
  "category": "boundary-abstraction",
  "status": "accepted",
  "files": ["src/api/create.ts", "src/api/update.ts", "src/api/import.ts"],
  "evidence": [
    {
      "file": "src/api/create.ts",
      "lines": "40-92",
      "symbol": "createHandler",
      "claim": "Validation rules are repeated with divergent defaults."
    }
  ],
  "why_it_matters": "Divergent validation can produce inconsistent writes.",
  "proposed_fix": "Move shared validation into the existing request schema layer and update callers.",
  "acceptance_criteria": ["All three entrypoints use one validation path."],
  "expected_checks": ["npm test -- validation", "npm run typecheck"],
  "risk": "medium",
  "dependencies": [],
  "estimated_effort": "medium",
  "reviewer": "deslop-reviewer",
  "created_at": "2026-05-31T00:00:00Z",
  "updated_at": "2026-05-31T00:00:00Z"
}
```

## Arbiter Result

```json
{
  "accepted": ["DSL-000001"],
  "rejected": [],
  "merged": [],
  "next": "DSL-000001",
  "stop_recommendation": null
}
```

## Verifier Result

```json
{
  "finding_id": "DSL-000001",
  "verdict": "PASS",
  "confidence": 0.91,
  "evidence": ["The three handlers now call the same validator."],
  "concerns": [],
  "required_follow_up": []
}
```

## Status Output

```text
Ultimate De-Slop Status
Score: 87
Findings by status: {'accepted': 2, 'verified': 1}
Findings by severity: {'P1': 3}
Next: DSL-000002
Stop file: absent
Loop outcome
  Stop reason: no_eligible_findings
  Priority note: P0/P1 clear; 2 P2 remain (not loop fuel at this priority)
  Verified this run:
    - DSL-000001 Share request validation
  Queued next: DSL-000002
  Needs human:
    - DSL-000004 Auth rewrite needs review
      Ambiguous logout semantics
  False positives:
    - DSL-000003 Speculative unused helper
      Helper is used by import path
Suggested commands:
  scripts/deslop-fix.sh DSL-000002
```

See also [proof-run.md](proof-run.md) for the deterministic control-plane proof transcript shape.
