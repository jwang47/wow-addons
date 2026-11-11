# wow-addons

> **`AGENTS.md` and `CLAUDE.md` must be byte-identical.** Edit one, copy it
> over the other, and check with `cmp AGENTS.md CLAUDE.md`.

LootValue, Omni, UpgradeFinder, QuestBoard, BuffCheck and Glance (in testing), WoW addons for the Forever client (interface 16001).
Read `README.md` first. Claude and Codex both work here, so durable facts
live in this repository, not in agent memory. This repo is public: keep
personal details (names of other people, machine paths, emails) out of it.

## Checks

From the repo root: `lua5.1 tests/lootvalue.lua`, `lua5.1 tests/omni.lua`, `lua5.1 tests/upgradefinder.lua`, `lua5.1 tests/buffcheck.lua`, `lua5.1 tests/questboard.lua`, `lua5.1 tests/glance.lua`, `lua5.1 tests/niceties.lua`, `lua5.1 tests/groupup.lua`,
`python3 -m unittest tests/test_release.py`. The `tests` workflow
runs them on every push and PR. Say in the PR which checks you ran.
To try a branch in the game, check it out in a wow-addons checkout and run
`dev.ps1 <Addon>` there (README, "Dev mode"); `dev.ps1 -Off` goes back to the
release.

**New code goes in a spare file, not a new file.** Each `.toc` ends with
empty `Spare1.lua` to `Spare5.lua`. A file that the `.toc` does not list
needs a full game restart; a spare loads with `/reload`. Use the next free
spare and say which one in the PR. Give a new addon five spares from the
start. Do not remove the last spare (a test checks it).

## Rules

- **Get explicit human confirmation before every publish**: a `release-*`
  tag (it makes the GitHub release that every friend's updater installs),
  and repository or Pages settings. State the exact action and
  target. A general "go ahead" confirms nothing.
- A change to an addon's files raises its `.toc` `## Version` and adds a
  `CHANGELOG.md` section in the same PR, once that version is live.
- Work on a branch and open a pull request.
- Never ask a human to paste a secret into a chat or a PR.
- Keep the account email out of everything you send: commits, issues, PRs,
  request headers. Commit as `jwang47@users.noreply.github.com` or the
  agent's own address.
- Never automate keys or read the game screen (ban risk); addons may only
  use what the game API allows.
- Use ASD-STE100 Simplified Technical English for explanations and PR
  bodies: short sentences, active voice.
- Never use `git stash`, and never undo a probe with `git checkout <file>`.
