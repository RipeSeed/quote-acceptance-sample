## Plan
<!-- docs/plans/<topic>.md -->

## What changed

## Tests added
- pgTAP:
- Vitest:

## Checklist
- [ ] RLS on every new table, explicit grants, a policy per granted command
- [ ] A pgTAP test per new or changed policy (allowed and denied role)
- [ ] No migration that is on `main` was edited
- [ ] `rls-reviewer` run on changed migrations
- [ ] Claude review: no open `[high]` findings
