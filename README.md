# wow-addons: LootValue, Omni and UpgradeFinder

Three small World of Warcraft addons for the WoW Forever client (a
Classic-based client, interface 16001). They should also work on other
Classic clients with the same APIs, but we test them only on Forever.

- **LootValue**: one tooltip line on each item that says whether to sell it
  on the Auction House, disenchant it or sell it to a vendor. It uses
  Auctionator's prices, so it needs Auctionator.
- **Omni**: one search box (Ctrl+Space) for your items, places, people,
  spells, quests and Questie NPCs.
- **UpgradeFinder**: a short list of gear from your Auctionator scan, your
  bags and the dungeon drops that beats what you wear, for any class and
  spec (`/uf`).

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
`Interface\AddOns\LootValue\LootValue.toc`,
`Interface\AddOns\Omni\Omni.toc` and
`Interface\AddOns\UpgradeFinder\UpgradeFinder.toc`.

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

## UpgradeFinder

UpgradeFinder is an addon for any class. `/uf`, the
**Upgrades** button on the Auction House, or a key binding opens a short
list: gear from your Auctionator scan, your bags and the dungeon drops that
beats what you wear, biggest gain first. Each row is one line (icon, name,
slot, `+gain`, then the price, "bags", or the dungeon's short name such as
`DM` or `BRD`); hover a row for the item tooltip plus the score you wear, the
gain per gold and what it replaces. Click searches the AH (when it is open;
for a dungeon drop it names the boss in chat), Shift-click links it. Drag the
bottom-right corner to resize the window; a taller one shows more rows. A pattern, plan or other recipe on the AH shows
as the gear it makes, tagged "craft" (its tooltip names the profession;
Scan.lua reads the made item's slot and stats from the recipe tooltip). Its
price is the craft cost: the pattern plus the reagents (from the line after
"Use: Teaches"), each at its Auctionator price or the vendor price when
lower; a "+" marks a reagent with no price. The tooltip lists the parts and
the price to buy the made item on the AH instead.

- Five buttons: **Slot** (click for the next, right-click for the previous),
  **Usable now / Up to +2 lvl**, **Biggest gain / Per gold**,
  **Any price / Can afford**, and **All sources / AH only / Dungeons / Bags
  only**. The choices are saved.
- Dungeon drops: `UpgradeFinder/Dungeons.lua` lists the boss and trash drops
  of the 25 Classic dungeons (Ragefire Chasm to Stratholme, no raids) by
  item ID, with each dungeon's level range. The scan reads them like AH
  items; IDs that are not gear (keys, quest items) drop out. The tooltip
  says "Drops from BOSS in DUNGEON (levels A-B)". An item that is also on
  the AH stays an AH row and gets the same line. Per gold puts dungeon drops
  after your bag items and before AH items. `/uf dungeons` turns them off
  and on. The table is game data and does not know Forever's own changes:
  the stats always come from the client's tooltip, but a drop Forever moved
  or removed still shows.
- What it changes (`UpgradeFinder/Stats.lua`): hover a row for the stat
  changes against the worn item(s) it replaces, then **Offense** and
  **Defense**, like Path of Building. The role comes from the weights in
  use (caster, healer, tank, ranged for a hunter, else melee). Rules:
  Stamina x10 health, Intellect x15 mana, Agility x2 armor; Intellect and
  Agility give crit at the level-60 ratios scaled down by level (for
  example 59.5 Int per 1% spell crit for a level-60 mage); attack power from
  Strength and Agility per class; armor reduction is
  `armor / (armor + 400 + 85 x level)`. The estimated DPS change is one cast
  of `4 x level + 20` base damage plus 0.8 x spell damage, with crits for
  +50% (melee: weapon DPS + AP / 14, crits for +100%), against your current
  totals from the game where it gives them (`GetSpellBonusDamage`,
  `GetSpellCritChance`, `UnitAttackPower`, `UnitArmor`). The numbers are
  estimates for comparing items, not a combat simulator.
- Build window (`UpgradeFinder/Build.lua`, `BuildUI.lua`): a gear planner
  like Path of Building. The working build starts as what you wear (item
  links, so enchants stay); drop an item on a slot (`GetCursorInfo`; it must
  fit the slot) or Alt-click an Upgrades row (it goes to the slot it would
  replace; a two-hander empties the off hand). The sheet sums the parsed
  stats of all 18 slots and runs `Stats.derive` on the difference, then
  shows now, build and change. Builds save per class in
  `UpgradeFinderDB.builds[class][name]` (slot -> link); Compare uses a saved
  build as the base instead of what you wear.
- Action bar DPS (`UpgradeFinder/Spells.lua`): `GetActionInfo` over the 120
  action slots finds your spells; `GetSpellDescription` gives the damage
  ("79 to 87 Frost damage", "222 Shadow damage over 18 sec"), `GetSpellInfo`
  the cast time, `GetSpellBaseCooldown` the cooldown, `GetSpellPowerCost`
  the mana. One rank per spell name (the strongest). Coefficient: measured
  (Calib.lua) or cast time / 3.5 s, duration / 15 s for damage over time.
  Rotation: a spell with a cooldown longer than its cast goes whenever ready
  if it beats the filler per second of casting; the filler (best damage per
  cast second) fills the rest. Order for a caster's Est. DPS: your logged
  spells, then the bars, then the generic cast.
- Calibration (`UpgradeFinder/Calib.lua`): when your gear, level or stats
  change (1 s after the last event), it saves a snapshot to
  `UpgradeFinderDB.calib[class].snaps`: level, Int, Agi, Sta (`UnitStat`),
  spell crit and crit minus the crit lines on your gear, max health, max
  mana, armor. Within one level, a least-squares slope over at least 4
  points of spread gives Int per 1% spell crit, Agi per 1% crit, health per
  Sta and mana per Int; another level uses the nearest measured one (crit
  ratios scaled by level). With `/uf calib log` on (Forever forbids it, see the client notes), from `COMBAT_LOG_EVENT_UNFILTERED` (your own
  `SPELL_DAMAGE` and `SPELL_MISSED` only) each spell ID keeps running sums:
  hits, crits, misses, damage, and non-crit unresisted hits against your
  spell damage then. After 20 such hits a spell joins the DPS model: its
  share of your damage, crit rate, average hit, and the coefficient (fitted
  once your spell damage spread is 15 or more, else cast time / 3.5 s).
  Est. DPS for a caster then uses your spells instead of the generic cast.
  `/uf calib` lists it all, `/uf calib reset` clears it for your class.
  Buffs that add crit directly can skew a snapshot; reset if a number looks
  wrong.
- eHP: health / (1 - armor reduction), physical hits only.
- Usable: no red line on the tooltip (armor type, weapon skill, class); a red
  "Requires Level" only hides it until you are within the level window.
- Score: a mage with MageMentor on uses MageMentor's score
  (`MageMentorAPI`), so the numbers match its tooltips. Everyone else uses
  simple leveling weights for their spec (`UpgradeFinder/Score.lua`): the
  talent tree with the most points picks them (for example a Protection
  warrior gets tank weights, a Holy priest healer weights; below level 10
  the class row applies). The window title shows the spec and the weights in
  use (a preset name or "custom"). The **Weights** button (or `/uf config`)
  opens a panel beside the window (`UpgradeFinder/Weights.lua`): a box per
  stat, gold when it differs from the default (empty it for the default);
  a name box with **Save** and **Defaults**; and a button per preset (click
  loads it, the x beside it deletes it). In chat, `/uf weight STAT N` changes a weight for
  your current spec (an unknown stat is refused), `/uf weight STAT default`
  undoes one, `/uf weight reset` goes back to the defaults, and `/uf weights`
  lists them. `/uf save NAME` keeps the weights in use as a preset for your
  class (`UpgradeFinderDB.presets`); `/uf load NAME`, `/uf presets` and
  `/uf delete NAME` use them. The weights are part of the saved-score key, so
  a change scores the items again (at once when the window is open). A new
  talent point that changes your spec starts a new scan.
- It reads every item ID in Auctionator's price database (gear can be keyed
  `g:ID:level`; the first number is the ID) through a hidden tooltip, 60 a
  frame. Items the client has not loaded come from the server: it asks for
  150 per pass, looks again every 1.5 s and adds upgrades as they arrive
  (footer "loading N more..."). It stops after 4 passes with nothing new;
  the footer then says how many did not load, and Rescan tries again.
  Gains are shown only once your own gear has loaded too: an equipped item
  whose tooltip is not ready (often just after login) would count as 0 and
  make every item for that slot look bigger. Random-suffix items ("of the
  Owl") are scored with their base stats.
- Rings and trinkets replace your weaker one; a two-hander replaces both
  hands; a one-hand or off-hand over a two-hander says so. A one-hand weapon
  counts for the off hand only once the game says you can dual wield
  (`CanDualWield`).
- Damage to one spell school ("Frost spells and effects") is its own stat,
  weighted per class and spec: a priest gets nothing for Frost damage.
- Changing gear or bags updates the list (also while it is closed, or at the
  end of a scan); an item you equip from your bags is no longer listed as
  free. An AH item with no known price never counts as affordable.

- Saved scores: item scores live in `UpgradeFinderDB.items`, so a /reload
  or the next login shows the list without reading the tooltips again.
  They are kept while the weights stay the same (the key holds the weight
  set, `Scan.VERSION`, and for a mage a fingerprint of MageMentor's
  weights). Worn gear scores are saved per item link, so the scan does not
  wait for your own gear after a login. Items that never loaded are skipped
  for a day; **Rescan** tries them again, `/uf reset` clears everything.
- Where to get it (with Questie on, `UpgradeFinder/Where.lua`): a row gets a
  blue tag when the item is free elsewhere: `quest` (a quest reward), the
  dungeon name (all its droppers are in that dungeon; Questie gives
  instance spawns as -1, -1), or `vendor`. Gear tooltips everywhere get
  "Get it:" lines (quest reward, drops from NPC (zone), world drop, sold by,
  chest, container); `/uf where` turns them off. Items Questie does not know
  (new Forever items) get nothing. Item keys used: `questRewards`,
  `npcDrops`, `vendors`, `objectDrops`, `itemDrops`.

## QuestBoard (in development)

A small floating list, under the minimap, of the quests that matter now.
It is not in the release yet (not in `tools/release.py` `ADDONS`); try it
with `dev.ps1 QuestBoard`. `/qb` shows or hides it.

| Group | What | Sorted by |
| --- | --- | --- |
| Active | quests in your log whose kill or loot count went up in the last 5 minutes (`ACTIVE_SECS`), or whose nearest open objective is within 200 yards (`HERE_YARDS`). It stays while you are within 600 yards (`STAY_YARDS`) or make progress, and 10 minutes after the last of either (`GRACE_SECS`) | most recent first, then nearest |
| Areas | places where 2 or more stops (objectives, hand-ins, givers) are within 250 yards of each other (`AREA_YARDS`), so one trip does several quests; the row says what is there ("2 hand in, 1 objective") | best XP per minute: the XP you earn there (hand-ins and objectives, not pick-ups) over the run there and the work |
| Turn in | quests in your log that are complete | nearest quest giver |
| In your log | the rest of your log, with the first open objective ("3/6") | nearest open objective (right-click the group: best XP) |
| Party has | quests your party members have that you do not (Questie's party data, `QuestieComms.remoteQuestLogs`), with who and their progress ("Ann 2/8") | nearest giver |
| Pick up | quests Questie shows as available ("!") that give XP and are at most 3 levels over you (`/qb range N`) | best estimated XP per minute (right-click the group: nearest) |

- A quest in your log that a party member also has says so under it ("with
  Ann 5/6"): the game's `IsUnitOnQuest`, plus Questie's party data for the
  progress. Party members need Questie too for their progress and for the
  Party has group.
- Focus (on by default): in combat and inside a dungeon or other instance,
  the board shows only the Next line and the Active group. Move the mouse
  over it and the whole board opens; it closes again a moment after the
  mouse leaves. Out in the world the whole board shows. `/qb focus` shows
  the whole board everywhere (again to undo).
- The top line says what to do next: the open objective of a quest you
  are on now (Active), else the best area when it has 3 or more stops, else
  the nearest hand-in, else the nearest quest.
- An item-started quest says where the item drops and who takes it in
  ("Loot Glowing Shard from Mutanus the Devourer, hand in to
  Sputtervalve"). A quest with nothing to kill (a letter to deliver) points
  to the NPC who takes it. A quest Questie has no place for says so once in
  chat and a click opens the quest log.
  Under each quest a dim line says what to do: the open objective and
  Questie's nearest mob, object or NPC for it ("Underbelly Whelp Scale:
  3/6 (Underbelly Whelp)"), or who takes it in. `/qb compact` drops that
  line.
- The level number is in the quest log colours (grey, green, yellow,
  orange, red). Each row shows the distance and an arrow that turns with
  you.
- Click a row: open the world map (M) at the place, and set and track the
  game's map pin there. Shift-click:
  link the quest in chat. Right-click: open the quest log (your quests) or
  show the giver with Questie's map icon (pick-ups). Hover: XP, the
  estimate, the giver or finisher, the open objectives.
- Click a group name to fold it. Drag the board (anywhere on it) to move it;
  `/qb lock` stops that and `/qb reset`
  puts it back. In combat it fades to 35%.
- `/qb tracker off` hides the game's quest tracker (and Questie's, if it
  is on); `/qb tracker on` brings it back. The game's tracker holds secure
  quest-item buttons, so in combat it only turns see-through and hides when
  combat ends.
- `/qb far on` turns on enemy nameplates at the longest range the client
  takes (it asks for 60 yards and reports what the game kept), so quest
  monsters and Questie's nameplate icons (`/questie`, Nameplates) show from
  further away. `/qb far off` puts the old settings back. Addons cannot mark
  monsters in the world or target them, so nameplates are the way.
- XP per minute is an estimate: the run to the place at 7 yards a second
  (or your speed when faster), 90 s per open objective, 30 s at the giver
  and 60 s back. The numbers are in `QuestBoard/Data.lua`.
- Data: Questie, when it is loaded (`QuestieDB.GetQuest`,
  `DistanceUtils`, `ActiveQuests`, `AvailableQuests.__availableQuests`,
  `QuestXP`, `ZoneDB` and HereBeDragons). Questie has no public API, so every
  call is guarded and a failing one only drops that piece. Without Questie
  the board shows your log only, with no places or XP.
- It refreshes on quest events and every 3 s for distances; each pass
  works at most 3 ms a frame (`ns.data.BUDGET_MS`).

## Forever client notes

- Addons may not use the combat log: registering for
  `COMBAT_LOG_EVENT_UNFILTERED` brings up "blocked from an action only
  available to the Blizzard UI" right after login. UpgradeFinder leaves it
  off (`/uf calib log` turns it on for this session only, for a client that allows it; confirmed
  in game on 2026-11-09: `forbidden: UNKNOWN()`, and a forbidden call turns
  it off again) and takes
  spell damage from the action bars instead. UpgradeFinder also says in
  chat which call the game blocked (`ADDON_ACTION_BLOCKED`/`_FORBIDDEN`)
  and keeps the last five in `UpgradeFinderDB.blocked`.

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
| `lua5.1 tests/upgradefinder.lua` | UpgradeFinder against a mock of the game API |
| `lua5.1 tests/questboard.lua` | QuestBoard against a mock of the game API and Questie |
| `python3 -m unittest tests/test_release.py` | Zips, manifest, version guard, changelog, page |

The `tests` workflow runs them all on each push and pull request. The real
check is in game.

### Dev mode: try a checkout in the game

WoW loads one folder per addon name from `Interface\AddOns`, so a
developer copy takes the place of the release copy. `dev.ps1` switches
one addon at a time (PowerShell, from this checkout):

```
powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 Omni
powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 -Status
powershell -NoProfile -ExecutionPolicy Bypass -File dev.ps1 -Off
```

`dev.ps1 Omni` moves the installed Omni to `<client>\wow-addons-prod\Omni`
and puts a link (a junction) to this checkout's `Omni\` in its place, so an
edit shows after `/reload`. `-Off` (with names, or for all) removes the
links and puts the release copies back. `-Status` lists each addon as dev or
release. It finds the WoW folder that `update.cmd` saved; give
`-Client "<_forever_ folder>"` otherwise. `update.cmd` never changes a
linked folder: it lists it as "dev copy" and ends with "In dev mode (not
updated): ...". Switch a branch with `git checkout` in this checkout and
`/reload`.

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
LootValue\, Omni\ and UpgradeFinder\>` writes `logs/wow-addons/` in the release layout;
then `update.ps1 -Client <test folder> -Manifest logs\wow-addons\addons.json`.

These addons started in Jiahua's private monorepo (`jwang47/scratch`,
`wow-mage/`) and moved here on 2026-11-09.

## License

MIT, see [LICENSE](LICENSE).
