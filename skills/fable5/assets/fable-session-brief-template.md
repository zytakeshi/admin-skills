# Frontier session brief — template

Frame every frontier-model session around producing **one durable artifact**,
not code. Fill this in and hand it to the frontier model together with the
distilled context pack.

---

## Target artifact
> Whichever fits — the durable decision the most downstream work depends on:
> spec/PRD/architecture doc · API-or-wire contract · data model/schema ·
> verification rubric + verdict schema · taxonomy/information architecture ·
> research plan · policy/decision record · fleet system-prompt.

**Artifact type:** …
**One-sentence goal of this artifact:** …

## Why this is a one-way door
> What breaks / how expensive is it to reverse once the week ends, data exists,
> or downstream consumers ship? (This justifies spending the frontier tier at
> all.)

…

## The decision(s) the frontier model must resolve
> The hard trade-offs. Be explicit — this is what the frontier model's
> capacity is *for*. Everything else is context, not the ask.

1. …
2. …

## Constraints & invariants that must hold
> What cannot break: wire-compat / byte-parity / existing contracts / security
> guards / platform limits for code; or the fixed facts, prior decisions, brand
> rules, and scope boundaries for a non-code artifact.

- …

## Downstream consumers of this artifact
> Who/what will build or run against it (so the frontier model optimizes for
> their needs).

- …

## Definition of done
> The artifact is self-contained enough that a cheap-fleet agent can implement
> or run against it WITHOUT re-asking the design questions.

- [ ] The frozen shape/contract/rubric is fully specified.
- [ ] The hard trade-offs are resolved with reasoning, not left open.
- [ ] A cheap-fleet agent (e.g. `/codex` / `/codexloop`, or your own equivalent) can act on it directly.

## Attached
- Distilled context pack (see `context-pack-template.md`) — NOT raw repo reads.
