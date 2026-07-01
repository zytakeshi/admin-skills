# Distilled context pack — template

Built by the **cheap fleet** (a call-graph/static-analysis tool if you have
one, plus a search/excavator agent) BEFORE the frontier session. The point is
to protect the frontier model's input tokens: hand it the distilled terrain,
not raw files. Keep this compact — a page or two, not a file dump.

---

## Scope
**Repo(s) / subsystem:** …
**The decision the frontier model is here to make:** … (mirror the session brief)

## Current shape (with file:line)
> Pull from a call-graph tool if available (trace references, symbol search,
> architecture summary); otherwise have an excavator agent read and cite
> directly. Cite exact symbols and locations — precision beats volume.

- Current contract/interface: `path/file.rs:NN` — …
- Key call sites / consumers: `path/file.go:NN` — …
- Relevant data model / wire format: `path/file:NN` — …

## Invariants that must hold
> What cannot break: wire-compat, byte-parity goldens, security guards, ordering.

- …

## Constraints & prior decisions
> Platform limits, existing tags/versions, things already chosen upstream that
> the frontier model should not relitigate.

- …

## Open questions for the frontier model
> The specific forks in the road. Everything above is context; THIS is the ask.

1. …
2. …

## Explicitly out of scope
> What NOT to redesign — keeps the frontier session focused on the one-way door.

- …
