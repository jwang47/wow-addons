# wow-addons: LootValue and Omni

Two small World of Warcraft addons for the WoW Forever client (a
Classic-based client, interface 16001). They should also work on other
Classic clients with the same APIs, but we test them only on Forever.

- **LootValue**: one tooltip line on each item that says whether to sell it
  on the Auction House, disenchant it or sell it to a vendor. It uses
  Auctionator's prices, so it needs Auctionator.
- **Omni**: one search box (Ctrl+Space) for your items, places, people,
  spells, quests and Questie NPCs.

Download page: https://jwang47.github.io/wow-addons/ (Windows installer).
Releases: [GitHub releases](https://github.com/jwang47/wow-addons/releases)
(one zip per addon). What changed: [CHANGELOG.md](CHANGELOG.md).

## Install

**Installer (Windows):** install
[Auctionator](https://www.curseforge.com/wow/addons/auctionator) first if
you want LootValue. Then download `update.cmd` from the download page and
double-click it. It finds your `_forever_` folder (or asks once), downloads
each addon that changed, checks its SHA-256 and replaces only that addon's
folder. Run it again whenever you want updates.

**By hand:** download the zips from the latest release and unzip each one
into `Interface\AddOns\` in your client folder, so that you get
`Interface\AddOns\LootValue\LootValue.toc` and
`Interface\AddOns\Omni\Omni.toc`.

Then restart the game fully. `/reload` does not find a new addon folder.

## LootValue

LootValue **requires Auctionator** (`## Dependencies: Auctionator`):
without it the game does not load LootValue. Run a Full Scan at the Auction
House now and then. On every item tooltip it adds
"LootValue: Vendor 10s  (or AH 10s, disenchant 4s)": what to do with the
item, then the other options in grey. "~" marks an estimate (the AH after
the 5% cut, the disenchant value).

- An AH sale is not sure. The AH comes first only when, after the cut and
  the deposit you lose if it does not sell (about 30% of the vendor price),
  it pays 1.5x the best sure option and at least 1s more; 2x when the market
  looks slow. Slow means 50+ listed (50+ full stacks for a trade good), a
  price that fell 10% since the last scan day, or a price 3+ days old, and
  the AH entry says which ("AH 57s (slow: 280 listed)").
- Disenchant shows for gear when you have Enchanting or know the Disenchant
  spell. Auctionator has no disenchant values on Forever, so LootValue
  estimates them from the Classic disenchant table and the AH prices of the
  materials ("disenchant: no price" when no value is known).
- A soulbound copy gets no AH option.
- With an AH price on the line, it says how old Auctionator's last scan is
  ("AH scan 3h ago").

Its functions are on the global `LootValue` table (`adviceLine`,
`marketInfo`, `ahWins`, `money`, `scanText`). Another addon can set
`LootValue.deferTo = "<its name>"` and draw the line itself; LootValue's own
tooltip hook then stays quiet. (Jiahua's private MageMentor addon does this.)

## Omni

Open it with **Ctrl+Space** (Omni takes that key at the first login only
when nothing else uses it; `/omni bind KEY` sets another key, and it is in
Key Bindings under "Omni") or `/omni [text]`. Type to search. Up/Down
move (the list scrolls; so does the mouse wheel), Tab and Shift+Tab jump
between groups, Enter acts, Shift+Enter or a right click does the second action,
Esc closes. A tooltip beside the box shows the selected result; item
tooltips get Auctionator's and LootValue's lines from those addons.

| Result | From | Enter | Shift+Enter |
| --- | --- | --- | --- |
| Items | bags (live), bank and mail (saved each time you open them), every item name in the Auctionator scan, `MageMentorDB.itemNames` (with MageMentor), and Questie quest items; the row shows the AH price and its age ("today", "3d old"), and the tooltip adds the last AH scan time | link in chat; at the Auction House, an Auctionator search; a Questie quest item you don't have: where it drops | link in chat |
| Places | every continent, zone, city and dungeon below the world map (`C_Map`); MageMentor's level range (green when it fits you) and hub | open the map there | |
| People | friends, guild, group, and the last 30 people you whispered with | whisper | invite |
| Spells | your spell book, top rank, no passives | put it on the cursor (not in combat) | link in chat |
| Commands | MageMentor's `/mm` commands (with MageMentor) | run it | |
| Your quest log | the quests in your log (a quest under a collapsed header is not listed); the row shows "done", the level and the zone | open the quest log at that quest | link the quest |
| Nearby | Questie NPCs with a spawn on the map you stand on, matched by name or title ("tailor", "bank", "flight"), nearest first; the row shows yards and the title | open the map at that spawn and pin it | |
| NPCs, quests | Questie's database, when Questie is on; a quest row shows its status ("in your log", "done", "needs level N" or "not taken") | open the map at the spawn, set and track the game's map pin, and show Questie's icon (a spawn on your own map first); a quest in your log (also under a collapsed header) opens the quest log, any other quest shows its start NPC | a quest in your log: show its start NPC |

Speed: each search runs a few milliseconds per frame (`ns.BUDGET_MS`, 4 ms)
and goes on next frame, so typing never stalls the game; a new keystroke
drops the old search. A query that extends the last one checks only the
last one's exact hits. Exact hits show first, fuzzy ones when their pass
ends. Enter finishes a search still running. `/omni perf` prints the last
search's work time and frame count.

Fuzzy: when a query has fewer than 8 exact hits (3+ letters), Omni also
matches skipped letters from a word's start ("rdg mach" finds Redridge
Machete) and one typo per word of 4+ letters ("machette"). For speed, a
typo in a word's first two letters is not matched ("mxchete" finds
nothing). Fuzzy hits rank below exact ones.

Filters: `i:` items, `p:` places, `@` or `w:` people, `s:` spells, `n:` NPCs,
`q:` quests (your log and Questie), `l:` your log only, `c:` commands,
`near:` or `nb:` nearby NPCs (alone: everything nearby, nearest first). An empty box lists what you used last.

Ranking: a name that starts with the query first, then names where each
query word starts a word, then names that only contain it. Inside each
tier, what you used most recently comes first, then items you own, places
that fit your level and people who are online. Each group shows at most 8.
The index is built when you open the box: Questie's tens of thousands of
NPCs, quests and items are read 2,000 a frame on the first open (the
footer says "reading Questie...").

Limits: the game only knows names of items you have seen or that are in a
scan, so Omni can't find a brand-new item by name. Omni never casts a
spell, uses an item or sends a key: the game blocks addons from that
outside a click on a secure button, so Enter puts a spell on the cursor
instead.

Check: `lua5.1 tests/omni.lua` from the repo root (a mock of the game API).
The API calls follow the `forever` branch of
Gethe/wow-ui-source: Forever has the newer `C_Container`, `C_SpellBook`
(skill lines and `GetSpellBookItemInfo` tables), `C_Map` and
`C_FriendList` APIs. Each call is guarded, so a missing one gives an empty
group, not an error.

## Forever client notes

- There is no global `GetItemInfo`; use `C_Item.GetItemInfo` or
  `C_Item.GetItemInfoInstant`. `/api search <name>` in chat lists what
  exists.
- `/reload` does not find a new addon folder. Restart the game once.
- Blizzard's own Forever UI source is public: the `forever` branch of
  [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).
  `Blizzard_APIDocumentationGenerated/` documents the `C_` functions.
  Check every new call there first.
- The Auction House window is the modern `AuctionHouseFrame`. It is
  load-on-demand, so it can be nil when an `AUCTION_HOUSE_SHOW` handler
  runs first: look again a moment later.

## Develop

Checks, from the repo root (Lua 5.1 and Python 3):

| Check | What |
| --- | --- |
| `lua5.1 tests/lootvalue.lua` | LootValue against a mock of the game and Auctionator APIs |
| `lua5.1 tests/omni.lua` | Omni against a mock of the game API |
| `python3 -m unittest tests/test_release.py` | Zips, manifest, version guard, changelog, page |

The `tests` workflow runs all three on each push and pull request. The real
check is in game.

## Release

1. In the PR: raise `## Version` in each changed addon's `.toc` and add its
   section to `CHANGELOG.md`. A test checks that each version has a section.
2. After the merge, with Jiahua's OK (it publishes to every friend): push a
   tag `release-YYYY-MM-DD` on that commit, or run the `release` workflow by
   hand with that tag name (it makes the tag on `main`). The `release` workflow runs the
   tests and `tools/release.py check` (it refuses an addon whose files
   changed since the latest release under the same version), then makes the
   GitHub release with `<Addon>-<version>.zip`, `addons.json`, `update.ps1`
   and `update.cmd`. `update.cmd` and `update.ps1` read
   `releases/latest/download/addons.json`, so friends get it at their next
   run.
3. The `pages` workflow publishes `site/` to GitHub Pages when `site/`
   changes on `main` (or run it by hand).

**Test build:** `python3 tools/release.py build --root <folder with
LootValue\ and Omni\>` writes `logs/wow-addons/` in the release layout;
then `update.ps1 -Client <test folder> -Manifest logs\wow-addons\addons.json`.

These addons started in Jiahua's private monorepo (`jwang47/scratch`,
`wow-mage/`) and moved here on 2026-11-09.

## License

MIT, see [LICENSE](LICENSE).
