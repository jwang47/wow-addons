# wow-addons

> **`AGENTS.md` and `CLAUDE.md` must be byte-identical.** Edit one, copy it
> over the other, and check with `cmp AGENTS.md CLAUDE.md`.

LootValue, Omni, UpgradeFinder, QuestBoard, BuffCheck, Workbench, Glance and Bazaar (in testing), WoW addons for the Forever client (interface 16001).
Read `README.md` first. Claude, Codex and Gemini all work here, so durable facts
live in this repository, not in agent memory. This repo is public: keep
personal details (names of other people, machine paths, emails) out of it.

## Checks

From the repo root: `lua5.1 tests/lootvalue.lua`, `lua5.1 tests/omni.lua`, `lua5.1 tests/upgradefinder.lua`, `lua5.1 tests/buffcheck.lua`, `lua5.1 tests/questboard.lua`, `lua5.1 tests/glance.lua`, `lua5.1 tests/niceties.lua`, `lua5.1 tests/groupup.lua`, `lua5.1 tests/bazaar.lua`, `lua5.1 tests/workbench.lua`,
`python3 -m unittest tests/test_release.py`,
`python3 -m unittest tests/test_agent_context.py`. The `tests` workflow
runs them on every push and PR. Say in the PR which checks you ran.
To try a branch in the game, check it out in a wow-addons checkout and run
`dev.ps1 <Addon>` there (README, "Dev mode"); `dev.ps1 -Off` goes back to the
release.

**New code goes in a spare file, not a new file.** Each `.toc` ends with
empty `Spare1.lua` to `Spare5.lua`. A file that the `.toc` does not list
needs a full game restart; a spare loads with `/reload`. Use the next free
spare and say which one in the PR. Give a new addon five spares from the
start. Do not remove the last spare (a test checks it).

## Agents and context files

Claude, Codex and Gemini all work here (owner, 2026-11-25: "make sure all
project context is available for both gemini and codex"). Codex and Gemini
4 Neon (Antigravity CLI `agy`) read `AGENTS.md` and `.agents/skills/`.
Claude Code reads `CLAUDE.md` and `.claude/skills/`.

- `AGENTS.md` is the source; `CLAUDE.md` is a byte-identical copy. Do not
  add a `GEMINI.md`: `agy` reads `AGENTS.md`, and a third copy can drift.
  (Source: the Antigravity CLI page in the Flutter docs,
  https://docs.flutter.dev/ai/antigravity-cli: `agy` reads `AGENTS.md`,
  keeps `GEMINI.md` only as a legacy name, and loads skills from
  `.agents/skills/`. `agy inspect` lists what it loaded; check it on the
  first run on a machine.)
- A skill lives in `.agents/skills/<name>/`, with a byte-identical copy in
  `.claude/skills/<name>/`.
- `python3 -m unittest tests/test_agent_context.py` fails when a copy is missing or different.
- **Agent memory is not a source.** Each tool's memory reaches that tool
  only. Write each lasting rule or fact here, in the README or docs, or in
  a skill, in the same PR. When a memory and the repository disagree, the
  repository wins; fix the one that is wrong.

## Review round

Every PR gets one review round from a reviewer that is not its author
before it merges. Pick the reviewer in this order (owner, 2026-11-25: "gemini 4
neon is the best model now"):

1. Gemini 4 Neon, once the shared review workflow in `jwhex00/runners`
   can run it on this repository. It cannot yet.
2. Codex GPT-6.2 Astra, by hand until this repository has a `/review` caller.
3. A fresh Opus 5.5 agent, when neither is available (Fable 5.2 for a
   high-risk change).

`@codex review` (the Codex cloud bot) does not count as the round. A review
that a human runs by hand and posts counts. Say in the PR which model
reviewed. If a fix or review loop goes several rounds without converging,
try another model instead of another round.

## Rules

- **Get explicit human confirmation before every publish**: a `release-*`
  tag (it makes the GitHub release that every friend's updater installs),
  and repository or Pages settings. State the exact action and
  target. A general "go ahead" confirms nothing.
- A change to an addon's files raises its `.toc` `## Version` and adds a
  `CHANGELOG.md` section in the same PR, once that version is live.
- Work on a branch and open a pull request.
- **Copy first, then change the client folders.** `WTF\` and
  `Interface\AddOns\` are not in git, and nothing may back them up. Before
  an agent edits, moves or deletes any file there (SavedVariables, `.wtf`
  files, an installed addon), copy each file it touches to
  `<client>\agent-backups\<yyyyMMdd-HHmmss>-<task>\` with the same
  relative path, and say that path in the reply and the PR. Close the game
  first: it writes SavedVariables on logout and `/reload`. `dev.ps1` and
  `update.cmd` keep their own copies and need no extra step. Procedure:
  README, "Copy before you change WTF or AddOns".
- Never ask a human to paste a secret into a chat or a PR.
- Keep the account email out of everything you send: commits, issues, PRs,
  request headers. Commit as `jwang47@users.noreply.github.com` or the
  agent's own address.
- Put each addon action on a button in its window, not only on a slash
  command.
- After each step, install the branch in the game client with `dev.ps1`
  (through a session on that machine), so the owner can try it: `/reload`
  for a change in a spare, a full game restart for a new addon folder or a
  `.toc` change.
- Never automate keys or read the game screen (ban risk); addons may only
  use what the game API allows.
- Use ASD-STE100 Simplified Technical English for explanations and PR
  bodies: short sentences, active voice.
- Never use `git stash`, and never undo a probe with `git checkout <file>`.
