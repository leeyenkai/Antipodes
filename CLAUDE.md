# CLAUDE.md

Claude Code reads this file automatically at the start of a session.

## → Read [AGENTS.md](AGENTS.md) first

[AGENTS.md](AGENTS.md) is the single working agreement for this repository: repository
layout, the module dependency rule, commands, Swift/SwiftUI/SwiftData conventions,
data-licensing rules, and the traps specific to this project. Everything that applies
to an AI agent working here lives there, so it stays in one place for every tool.

Product requirements live in [docs/SPECIFICATION.md](docs/SPECIFICATION.md), with
stable requirement IDs (`R-…`) and open questions (`Q-…`). Release history is in
[CHANGELOG.md](CHANGELOG.md).

## The short version

- **Antipodes** is a privacy-first iPhone/iPad/Mac travel logger with deep statistics.
  No account, no server, no analytics; everything works offline.
- Logic and UI live in the `AntipodesKit/` Swift package. `Antipodes.xcodeproj` is a
  thin app shell. Run `scripts/check.sh` before finishing.
- `AntipodesCore` depends on nothing; `AntipodesStats` is pure and must never import
  SwiftData. That is what keeps `swift test` fast and hermetic.
- `[M1]` and `[V1]` work is in scope (decision D-18); §13.1 of the spec says what is
  blocked. Do not build `[LATER]` features early.
- Cite requirement IDs in commit messages, and add a `[Unreleased]` line to the
  changelog as part of the change.

Anything in this file that disagrees with AGENTS.md is out of date; AGENTS.md wins.
