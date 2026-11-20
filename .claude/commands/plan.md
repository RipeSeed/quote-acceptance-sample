---
description: Write the plan for a database or Edge Function change, before any code
argument-hint: <topic>
allowed-tools: Read, Grep, Glob, Write(docs/plans/**)
---

Write `docs/plans/$ARGUMENTS.md` for the change we discussed. Do not write migrations or code yet.

First read `CLAUDE.md`, `.claude/rules/`, the existing migrations and the tests. Then write these sections:

1. **Goal:** one or two sentences.
2. **Tables and columns:** what is new or changed, with types and constraints.
3. **Access:** a table of roles (`admin`, `office`, `technician`, `anon`, `service_role`) against commands (select, insert, update, delete), with each cell saying allowed or denied.
4. **Grants and policies:** the exact grants, and the exact policy names you will create.
5. **Functions and triggers:** the signature, whether it is `security definer` or `invoker`, and why.
6. **Tests:** the pgTAP cases (one allowed and one denied role per policy) and any Vitest cases.
7. **Out of scope and open questions.**

Stop after writing the file and ask for approval.
