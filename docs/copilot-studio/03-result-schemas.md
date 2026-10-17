# Esquemas JSON para *Parse JSON* en Power Automate

## Diagnóstico (`results/diagnosis/<id>.json`)
```json
{
  "type": "object",
  "properties": {
    "kind": { "type": "string" },
    "id": { "type": "string" },
    "status": { "type": "string" },
    "drift": { "type": "boolean" },
    "summary": { "type": "string" },
    "change_count": { "type": "integer" },
    "changes_md": { "type": "string" },
    "evidence_md": { "type": "string" },
    "evidence_source": { "type": "string" },
    "fingerprint": { "type": "string" },
    "run_id": { "type": "string" },
    "run_url": { "type": "string" },
    "issue_url": { "type": "string" },
    "issue_number": { "type": "string" },
    "requested_by": { "type": "string" },
    "reason": { "type": "string" },
    "identity": { "type": "string" },
    "started_at": { "type": "string" },
    "finished_at": { "type": "string" }
  }
}
```

## Corrección (`results/remediation/<id>.json`)
```json
{
  "type": "object",
  "properties": {
    "kind": { "type": "string" },
    "id": { "type": "string" },
    "diagnosis_id": { "type": "string" },
    "status": { "type": "string" },
    "summary": { "type": "string" },
    "decision": { "type": "string" },
    "changes_md": { "type": "string" },
    "verified": { "type": "boolean" },
    "approved_by": { "type": "string" },
    "rejected_by": { "type": "string" },
    "approval_comment": { "type": "string" },
    "requested_by": { "type": "string" },
    "justification": { "type": "string" },
    "identity": { "type": "string" },
    "run_id": { "type": "string" },
    "run_url": { "type": "string" },
    "finished_at": { "type": "string" }
  }
}
```
(Sin `required`: así un resultado de error o rechazo no rompe el Parse JSON.)
