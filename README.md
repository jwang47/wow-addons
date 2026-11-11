# wow-addons: LootValue, Omni, UpgradeFinder, QuestBoard and Glance

Small World of Warcraft addons for the WoW Forever client (a
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
- **QuestBoard**: a small board of the quests that matter now: what you
  are doing, what to hand in and the best quests to pick up nearby, with
  XP, rewards and distances (`/qb`). Questie adds places and pick-ups.
- **Workbench** (in testing, not in the releases yet): one window for
  crafting, with every recipe by profit and the cheapest next skill point
  (`/wb`). It needs UpgradeFinder.
- **Glance** (in testing, not in the releases yet): a lighter HUD with a
  keyboard-shaped action bar, a square minimap and small floating unit
  frames (`/glance`).

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
`Interface\AddOns\Omni\Omni.toc`,
`Interface\AddOns\UpgradeFinder\UpgradeFinder.toc` and
`Interface\AddOns\QuestBoard\QuestBoard.toc`.

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
- With an AH price on the line, it says how old Auctionator's last full
  scan is ("AH full scan 3h ago"). An item that a full scan today did not
  see says "not in today's full scan": nobody lists it now, and its price,
  listings and trend are from an older day. Auctionator counts price days
  from local midnight, so an item seen only last night is "1 day old" in
  the morning.

### Auto-loot

LootValue also loots for you and leaves cheap junk (murloc fins and the
like) on the body. It is on by default; `/lv` shows the settings.

- Always taken: money, quest items, green or better, cloth, leather, ore,
  herbs and other materials, consumables, recipes, bags, keys, reagents,
  and any item the game has no info for yet.
- Other items (grey junk, white meat and parts): taken when the stack is
  worth at least 10c a character level (2s80c at level 28). The value is
  the best of vendor, AH (only when the AH clearly pays more, as on the
  tooltip) and disenchant. With 3 or fewer free bag slots the bar is 3x.
  An item that fits on a stack you carry needs no slot, so any value takes
  it. `/lv autoloot min 5s` sets your own bar; `min auto` goes back.
- **review** mode (the default): the loot window stays open on what it
  left, so you can click an item to take it after all. **quiet** mode
  (`/lv autoloot quiet`): the window closes and one chat line lists what
  it left. It never closes the window while a wanted item is still there
  (bags full, a bind confirmation).
- Shift+loot (the game's auto-loot key) takes everything. Fishing loot is
  always taken whole.
- `/lv skipped` lists the last 10 items it left (30 are kept).
- `/lv autoloot off` turns it off. While it is on it keeps the game's own
  Auto Loot option off (it can only choose when the game does not take
  everything first), and `off` puts your old setting back.

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
| Items | bags (live), bank and mail (saved each time you open them), every item name in the Auctionator scan, `MageMentorDB.itemNames` (with MageMentor), and Questie quest items; the row shows the AH price and its age ("today", "3d old"), and the tooltip adds the last AH scan time | where to get it (`from: Linen Cloth`, with Questie): the mobs that drop it, the objects that hold it and the vendors that sell it, nearest first with yards on your map, else the zone; Enter on one opens the map and pins it. At the Auction House, an Auctionator search. With no Questie source: link in chat | link in chat |
| Places | every continent, zone, city and dungeon below the world map (`C_Map`); MageMentor's level range (green when it fits you) and hub | open the map there | |
| Dungeons | the Classic dungeons by name or short name ("bfd", "sm gy", "brd"); the row shows the levels (green when they fit you), the short name and the boss count. Data: `Omni/Dungeons.lua`, a copy of `UpgradeFinder/Dungeons.lua` (a test checks that they match) | list its loot: `loot: BFD` shows one group per boss with its drops, then the dungeon's quests (with Questie) and their reward items. Hover an item for its tooltip, Enter links it; Enter on a quest shows where it starts | |
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
`d:` dungeons, `loot:` one dungeon's drops and quests (`loot: bfd`),
`from:` where to get an item (`from: linen cloth`),
`near:` or `nb:` nearby NPCs (alone: everything nearby, nearest first). The Nearby group always comes first. An empty box lists the 5 nearest NPCs, then what you used last.

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

- Crafting lines (`UpgradeFinder/Craft.lua`): hover a recipe item (in your
  bags, at a vendor, on the AH) or a recipe in your profession window (the
  recipe list rows and the made item's icon) and the tooltip adds:
  **Cost to craft** (the reagents at the AH price, or the vendor price when
  lower; "+?" and a "No price:" line for a reagent with no price),
  **Sells for** (the best of the AH after the 5% cut, the vendor and, with
  Enchanting and LootValue, the disenchant estimate; times the number
  made), **Profit** or **Loss**, and for gear the **Score of the made item**
  against what you wear (MageMentor's score for a mage with MageMentor).
  A bind on pickup item sells only to the vendor. An enchanting formula
  makes no item, so it gets the cost only. On a recipe tooltip the game
  reports the made item, so that gives its price. A recipe names its
  reagents only by name, and the game finds an item by name only once the
  client has seen it; so UpgradeFinder learns the names of the items in the
  Auctionator scan in the background, starting 5 s after login (names the
  client knows at once, others asked from the server 150 per 1.5 s), and saves them in
  `UpgradeFinderDB.names`. A reagent that shows "No price" at first gets
  its price on the next hover. A material you can turn into another item
  with one reagent (Silk Cloth into Bolt of Silk Cloth, ore into bars)
  gets a "Make into" line: what one craft gains or loses, with the cost
  and the sale ("+7s 50c (40s -> ~47s 50c)"). The cloth bolts are built
  in; other such recipes are read each time you open a profession window
  and saved in `UpgradeFinderDB.recipes`. `/uf craft` turns the lines off
  and on.
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

## GroupUp (in development)

A panel that gives you the numbers to decide whether to group up. `/gu`
shows or hides it. It is not in the release yet (not in `tools/release.py`
`ADDONS`); try it with `dev.ps1 GroupUp`.

| Part | What it shows |
| --- | --- |
| Top line | Which way the numbers lean ("Leans group", "Leans solo", "About even") and why. |
| XP per hour | Your measured XP per hour solo, and in each group size you played in, at your level and the 2 levels below. Rested bonus XP is left out, so solo and grouped compare fairly. Each row also has the play time, the XP a kill, the kills a minute and the part of the XP from quests. A number shows after 5 minutes of play in that group size. |
| Kill XP in a group | Your share of the solo kill XP: in your group now (by level), or for a group of 2 to 5 at your level when you are solo. A warning when a member is so far above you that mobs at your level are grey for them (kill XP is worked out from the highest level in the group, so nobody gets XP). |
| Your quests | Each open quest with what a group does for it: "needs a group" (an Elite, Group or Dungeon tag, or a suggested group size), "kills count for all" (kill objectives left), "drops or clicks" (only item or object objectives left) or "talk or explore". "+Name" shows the party members who have the quest too. |

**Pinned quests.** When you pin quests in QuestBoard (Alt-click a row: "I'm
doing this"), GroupUp judges only those. The top line says "for your pins",
the list is "Your pinned quests (QuestBoard)", and one line counts the
other quests in your log. A pinned quest that you have not taken yet shows
"not taken yet" (or "needs a group" when it has a group tag). With no pins,
GroupUp judges every quest in your log, as before.

**From QuestBoard.** With both addons on, the tooltip of a QuestBoard quest
row has a "Group: ..." line with the GroupUp verdict. Ctrl-click a quest row
to open the GroupUp panel with that quest at the top ("Asked about");
Ctrl-click it again to close the panel. GroupUp adds this from its side, so
QuestBoard works the same without GroupUp.

How it works, and what to keep in mind:

- Classic splits kill XP: the group gets the kill XP times a bonus (1x for
  2, 1.166x for 3, 1.3x for 4, 1.4x for 5) and each member near the kill
  gets a part by level. In a duo of the same level you get 50% a kill, so
  the duo must kill twice as fast to keep up. Quest XP is never split.
- A kill counts for the kill objectives of every member near it, so a kill
  quest goes about as many times faster as there are members on it.
- Drops and clicks are less clear: some quest items drop for each member
  who needs them, some do not, and each member clicks their own objects.
  The measured XP per hour is the real test.
- The time count stops at a gap of more than 10 minutes with no XP (a
  break). Time in town and on the road counts, because it is part of the
  cost of each way to play.
- When someone invites you, two lines go to chat: the quest counts and
  your solo and grouped XP per hour. `/gu invite off` stops that; `/gu
  sum` prints them at any time.
- **Thanks & leave**: while you are in a group, a button above the party
  frames says "thx for party" in party chat and leaves the group 5
  seconds later. Press it again in that time to stay. `/gu bye` does the
  same. `/gu bye text ...` sets the words (empty: leave without a word),
  `/gu bye delay N` the seconds (up to 60), `/gu button off` hides the
  button. Shift-drag moves it.
- `/gu reset` moves the panel and the button back, `/gu clear` forgets the
  XP data of this character. Drag the panel to move it; right-click hides it.
- The data is per character, in `GroupUpDB` (SavedVariables).

## Niceties (in development)

A home for small nice-to-haves. Each one is a file in `Niceties/` and can be
turned off. It is not in the release yet (not in `tools/release.py`
`ADDONS`); try it with `dev.ps1 Niceties`.

`/nice` lists the features and their state. `/nice KEY` toggles one,
`/nice KEY on|off` sets it. The state is in `NicetiesDB` (SavedVariables).

| Key | What it does |
| --- | --- |
| `zoom` | Max camera distance (on by default). Sets the `cameraDistanceMaxZoomFactor` CVar to the highest value the client keeps, at each login and loading screen, so you can scroll the camera out much further. The Options slider stops at 2.0; the addon tries 4.0, 3.4, 2.6 and 2.0 and keeps the first one the client takes (or the value the client clamps it to). Off puts back the value you had before. Moving the Options slider changes it until the next login. |

To add a feature: put it in the next free `SpareN.lua` (the `.toc` already
lists five empty ones, so the game loads it after `/reload`; a new file
that is not in the `.toc` needs a full restart) and call
`ns.Add({ key, name, help, apply = function(on, data, why) end })`.
`apply(true)` runs at each login and when it is turned on, `apply(false)`
only when it is turned off. Rename the spare file and add a new spare in
the release that ships it.

## Workbench (in development)

**Workbench: Crafting Profit and Skill-ups** is one window for your
professions (`/wb`). It is not in the release yet (not in `tools/release.py`
`ADDONS`); try it with `dev.ps1 Workbench`. It needs UpgradeFinder
(`## Dependencies`), and an UpgradeFinder that has `UpgradeFinderAPI.known`
(the recipe list, from "Omni: search recipes").

- UpgradeFinder reads your recipes when you open a profession window, and
  a trainer's recipes when you visit the trainer. Workbench shows that
  saved list, so it works with the windows closed. The list is as old as
  your last visit.
- **Profit** view: each recipe with the cost to craft, what the made item
  sells for (the best of AH after the cut, vendor and disenchant; "~" marks
  an estimate) and the profit, best first. Recipes with no price for the
  made item come last.
- **Skill-ups** view: what one skill point costs with each recipe, cheapest
  first. A craft costs its reagents less what the made item sells for. A
  recipe that pays for itself shows "free". Orange gives a point each
  craft. The game does not give the chance for yellow and green, so
  Workbench uses 75% and 25% (`L.CHANCE` in `Workbench/Logic.lua`) and marks
  those costs with "*": a guide, not a promise. Grey recipes are left out.
- The recipe name has its skill-up colour. Three buttons: the profession
  (click for the next, then all), the view, and **My recipes / With
  trainer**. With trainer adds the recipes you do not know, in grey, with
  the skill they need and the training price; the Skill-ups view counts the
  ones you can learn now.
- Hover a row for the made item's tooltip and the numbers. Shift-click
  links the item in chat. The mouse wheel scrolls.
- It opens beside the profession window on that profession, and closes
  with it. `/wb dock` turns that off; `/wb` shows or hides it anywhere;
  `/wb profit` and `/wb skill` pick the view; `/wb reset` moves it back.
- Plan: Workbench becomes the home for crafting. The crafting tooltip
  lines and the shopping list (now in UpgradeFinder) move here once their
  pull requests are merged.

## QuestBoard

A small floating board, under the minimap, of the quests that matter now.
`/qb` shows or hides it. Four tabs follow what you are doing:

| Tab | When | What |
| --- | --- | --- |
| Doing | picked by itself while a quest is Active | the quests you are on (each open objective, party, chain), then "On the way": hand-ins, pick-ups and party quests within 300 yards of you or of an Active quest (`ns.ON_WAY_YARDS`), then "Your party", then one line that counts the rest of your log ("11 more in your log: Log tab") |
| Nearby | picked by itself when no quest is Active | "Chain next": one list of what to do next within 1000 yards (`ns.NEXT_YARDS`): hand-ins, open objectives, pick-ups, party quests you can take, and areas with 3 or more stops in place of those stops. Best XP per minute first, the walk counted; a hand-in within 600 yards (`ns.TURNIN_TOP_YARDS`) first. Then "Your party" and the line for the rest of your log |
| Areas | click it | "Where to go": every zone with stops you know (your log, hand-ins, pick-ups near and far), the ones you can reach first by XP per minute with the trip counted, far ones after by XP; each row says what is there ("3 in your log, 4 pick up"). Then "Travel": the nearest innkeeper and flight master |
| Log | click it, or the "more in your log" line | every quest in your log under its log zone, one line each, never cut. A quest with no known place says "no place" |

Alt-click a list's heading (Chain next, On the way, a Log zone) to pin
every quest you see in it, the stops of its areas too; they go to Doing
together. Alt-click it again to unpin them. Alt-click a zone in Areas to
pin every quest there (far pick-ups too), for a zone you swap to.

A quest you finish stays in Doing as a hand-in: a pinned one until you
hand it in, else for 10 minutes after your last progress. Pinned quests
also sit in a "Pinned" list at the top of the other tabs.

A tab you click holds until the board's own pick changes (you start or
finish a quest). Active means: the kill or loot count went up in the last
5 minutes (`ACTIVE_SECS`), or you Alt-clicked the quest (any quest, also a
hand-in or a pick-up). It stays while you are within 600 yards
(`STAY_YARDS`) or make progress, and 10 minutes after the last of either
(`GRACE_SECS`).

- A quest in your log that a party member also has says so under it ("with
  Ann 5/6"): the game's `IsUnitOnQuest`, plus Questie's party data for the
  progress. Party members need Questie too for their progress.
- Focus (on by default): in combat and inside a dungeon or other instance,
  the board shows only the quests you are on. Move the mouse over it and
  the whole tab opens; it closes again a moment after the mouse leaves.
  `/qb focus` shows the whole tab everywhere (again to undo).
- An item-started quest says where the item comes from (a mob that drops
  it, a chest or crate that holds it, or a vendor) and who takes it in.
  When Questie does not know (a world drop), the row says "drop unknown"
  and the distance is to the one who takes it in
  ("Loot Glowing Shard from Mutanus the Devourer, hand in to
  Sputtervalve"). A quest with nothing to kill (a letter to deliver) points
  to the NPC who takes it. A quest Questie has no place for says so once in
  chat and a click opens the quest log.
  Under each quest a dim line says what to do: the open objective and
  Questie's nearest mob, object or NPC for it ("Underbelly Whelp Scale:
  3/6 (Underbelly Whelp)"), or who takes it in. `/qb compact` drops that
  line.
- The Doing tab groups its quests by stop: quests whose places are within
  150 yd of each other are one trip. A stop's line shows how far it is
  (with the arrow), what you do there ("1 hand-in, 2 pick-ups") and what
  it pays: the XP of its hand-ins and the run there, else the XP and time
  of its quests ("~" is a guess). Each quest under it is one line with a
  mark: a gold "?" to hand in, a gold "!" to pick up, a grey "?" to
  finish, which keeps its objectives under it. A small square after the
  name means gear; the tooltip names it. Hand-ins lead: a quest you can
  hand in within 600 yd is always in Doing and its stop is first (best XP
  per minute of the run first), and a farther hand-in joins a stop already
  shown at its place. `/qb stops` goes back to one list
  (the code is in `QuestBoard/Spare1.lua`).
- Travel time is an estimate. Near places are a run in a straight line
  at your speed. From 1500 yd, the trip is the shorter of the run and a
  flight (run to the nearest flight master, a straight flight at 30 yd per
  second plus 20 s, run from the flight master nearest the place); the
  board assumes you have the flight path. Another continent counts a flat
  15 minutes for the boat or zeppelin. The constants are in
  `QuestBoard/Spare2.lua` and are not measured in the game yet.
- A dungeon, raid or group quest has a tag after its level: 28D, 40R, 22G
  (`GetQuestTagInfo`, else Questie's `GetQuestTagInfo`, else the suggested
  group size). `/qb dungeons off` keeps dungeon and raid quests to the Log
  tab (out of Doing, Nearby and Areas) and leaves their pick-ups out.
- The level number is in the quest log colours (grey, green, yellow,
  orange, red). Each row shows the distance and an arrow that turns with
  you. The distance is green within 300 yards, yellow up to 1000 yards and
  grey beyond (`D.NEAR_YARDS`, `D.MID_YARDS`).
- An Active quest with more to say gets a line per open objective (the
  first with where to find it), a "Party:" line with each member's
  progress, and the chain tag, up to 5 lines (`ns.ACTIVE_LINES`).
- `/qb party off` hides party members' quests on the board and sets
  Questie's `showPartyQuestObjectives` to off (its old value comes back
  with `/qb party on`).
- Minimap pointers: when Glance is loaded, QuestBoard gives its minimap
  edge arrows the best next stop's place, the nearest hand-in and the Town
  rows (`Glance.minimap.addPointerSource`, a list cached per refresh).
- XP colours: in each group, the best third of the XP (Turn in) or XP per
  minute (Pick up, Party has, Areas) is green and the worst third grey
  (`D.tier`), so the better quests stand out.
- A Turn in row shows the XP, the run time to the finisher (distance at
  your current speed, at least run speed, `D.RUN_SPEED`) and the best item that the quest gives
  ("[Murloc Charm] +1" when you choose one of two), or "no item". When the
  chain goes on to better gear, the row says so ("chain -> [Axe]"). The
  item index comes from Questie's item data (`questRewards`). Hover the
  row for the XP per minute of the trip. Questie's distance is in world
  yards, so a finisher in the next zone counts the full run; one on
  another continent shows "far".
- Time left: once you kill or loot for a quest, the board learns your pace
  (seconds per kill or loot, on that quest and over all quests; a break
  over 5 minutes is not counted). An Active row shows
  about how long the rest takes ("~4 min"): the run there plus the kills
  left at your pace. XP per minute uses the same estimate.
- A quest in your log that is not done has a thin progress bar along the
  bottom of its row (each objective weighs the same): gold in Active,
  blue elsewhere.
- A quest you Alt-clicked (pinned) has a gold star before its name.
  Alt-click an area to pin every quest there at once (again
  to unpin them); the area gets the star when all of them are pinned.
- "Nearest" sorting goes by distance only up to 1000 yards
  (`D.MID_YARDS`). Quests further away, in another zone or on another
  continent come after them, biggest XP first, because the travel guess
  counts for little there.
- Size: drag the grip at the bottom right corner: up and down sets the max
  height, sideways the width (220 to 560, `/qb width N`). While you drag, a
  gold outline shows the max size with its numbers. Or `/qb height N`.
  The title and the tabs stay; the rows scroll with the mouse wheel,
  one line at a time, and a dim line says how many rows are above and
  below. Right-click the grip or `/qb height off` for no limit.
- Click a row: open the world map (M) at the place, and set and track the
  game's map pin there. Shift-click:
  link the quest in chat. Right-click: open the quest log (your quests) or
  show the giver with Questie's map icon (pick-ups). Hover: XP, the
  estimate, the giver or finisher, the open objectives.
- Chains: the what-to-do line ends with what the quest leads to. "chain +2
  -> [Ironforge Gladius]" (in the item's colour) means the best reward is
  gear two quests further down the chain; "XP only" means no gear anywhere
  in it, so the quest is fine to drop if the XP is not worth it. It walks
  Questie's `nextQuestInChain` and, once per session, reads every Questie
  item's `questRewards` (a slice per frame) to find each quest's rewards.
  It does not yet say whether the gear is an upgrade for you.
- Quest items: a button just left of each quest row that has a usable
  quest item (the game's `GetQuestLogSpecialItemInfo`, else Questie's
  `sourceItemId` when you carry it and it has a use); at most 6, Active
  quests first. A quest whose row is hidden (trimmed, collapsed or
  scrolled away) shows no button. Click one to use it; hover for the item
  and its quest. The buttons are secure, so the game locks them in combat:
  they are placed by screen position (not anchored to the board, which
  would lock the board too), and a change made in combat waits for the
  fight to end.
- In a group, "Your party" has a row per member: level, health or
  offline / dead / AFK, yards and arrow (or zone), and your quests they
  share ("1 behind": you can hand it in, they cannot yet). Point at it for
  their progress on each one; click pins them on the map.
- A list with more rows than it shows ends in a "+N more: ..." line that
  names them (click it for the whole list). `/qb why NAME` says where a
  quest is on the board, or why it is not there.
- Point at a quest to see its whole chain in the tooltip: each step with
  its level, marked done, `>>` (this one), log or `...` (later). Each step
  not done shows its XP and minutes (the trip plus the work, a guess), and
  `+gear` when it rewards gear. The heading sums what is left ("4 left:
  6.2k xp, 25 min") and splits the time into travel and questing. The trip
  goes from where the step before ends; `~` marks a step with no known place.
- Alt-click any quest row: "I'm doing this" (it stays in Active until
  you Alt-click it again or hand it in). This works for hand-ins and
  pick-ups too: a pinned pick-up waits in Active until you take it.
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
- Level weight: a quest over your level counts slower (`D.levelFactor`:
  1.25x at +1, 1.6x at +2, 2.2x at +3, 3.2x at +4, 6x at +5 or more; 0.85x
  at 3 or more under), in time left and XP per minute, until your own pace
  on that quest is measured. The tooltip says so.
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

## BuffCheck

**BuffCheck: Party Buffs at a Glance** shows your buffs and your group's in a
small grid (`/buffs`). It is not in the release yet.

- One row for you and one for each party member (in a raid: your
  subgroup). One column for each buff your group can give: Int (mage),
  Fort (priest), Wild (druid), Bless (paladin, any Blessing). Your own row
  also has an Armor column (mage armors, Inner Fire, Demon Armor).
- Green: the buff is on. Yellow with minutes left: it ends in under 3
  minutes. Red `x`: missing. Grey `?`: unknown (the member is too far, or
  the client hides the aura). Warriors and rogues get no Int cell.
- Click a row to cast your buff on that person (on your own row: your
  armor when your buff is already on).
- **Scrolls**: when your bags hold a stat scroll (Intellect, Stamina,
  Spirit, Protection, Strength, Agility) or a Forever weapon imbue scroll
  (Scroll of Imbue Frost and the others), your row gets a Scroll column.
  Red with a number: that many scrolls you can use whose buff is not on
  you. Green: all on. Dark `-`: none of them is of use now. The tooltip
  lists each scroll that is not counted and why: no use to your class
  (Agility for a mage), a class buff that is better and does not stack
  (Arcane Intellect, Fortitude), an imbue for another weapon type (staff,
  dagger or sword in your main hand), or a level too low.
- An imbue counts as on when your main hand has any temporary enchant
  (`GetWeaponEnchantInfo`), an oil too. Next reads the best scroll after
  your armor; an imbue goes on the main hand (`/use 16`). The stat scroll
  buff names (Stamina, Intellect, Armor and so on) are from Classic; check
  them in game on Forever.
- The **Next** line under the grid names the next person to buff and why,
  and a click casts on them. Bind a key to it in Key Bindings > BuffCheck.
  The order: a stranger who buffed you (return the favour), your group
  (missing, then under 1 minute left), your armor, your scrolls, then players within
  about 10 yards without your buff. It gives your target back after a
  cast on a stranger. Right-click skips that person for 10 minutes.
- Next is empty while you are mounted. It does not offer nearby players
  below 30% mana. `/buffs nearby off` stops the nearby offers.
- Nothing changes in combat (the game locks the buttons), and Next says
  "In combat". The game hides buff names in combat, so the colours come
  from the last read before the fight: a buff counts as on until its end
  time. Drag the header to move the grid; `/buffs reset` moves it back,
  `/buffs` hides or shows it.
- It replaces the third-party Manners addon: turn Manners off in the
  AddOns list so that the two do not both prompt you.

## Glance

A lighter HUD (`/glance`), still in testing: it is not in the releases
yet. Try it with `dev.ps1 Glance` (see "Dev mode"), then restart the game
once. The design mockups are in [docs/glance.md](docs/glance.md).

- **Keyboard bar** (bottom centre): one button per key of the left hand,
  laid out like the keyboard: 1-6, Tab Q W E R T, A S D F G and
  Z X (C, V and B stay with the game). At the first login Glance reads each key's binding. A key that
  fires an action button (Blizzard's bars or Bartender4's) keeps that slot,
  so your spells show on the keys they are already on. A free key gets an
  empty slot. Movement keys (dashed, with an arrow) and keys with another
  command (Tab: Target) keep their binding.
  - Drag a spell from the spell book onto a key to put it on that key.
    That is the whole binding: no Key Bindings window.
  - Hold Shift: the bar shows the Shift layer, and a drop goes there. The
    small icon in a key's corner is its spell on the other layer.
  - Drag a spell from one key to another to move it; drop it on a key that
    has a spell and the two swap. `/glance lock` makes drags need Alt, so a
    stray drag cannot move anything.
  - `/glance edit`: drag the gold area around the keys to move the bar;
    `/glance reset` puts it back. Nothing moves in combat (the game locks
    action buttons then).
  - `/glance take F` puts a key with another command on the bar;
    `/glance free F` gives it back. `/glance take all` takes every key with
    another command (F: Assist, Z: Sheathe and so on), except
    Tab, the bag keys and the character pane (B and C, with their Shift
    layers, keep their commands) and the
    movement keys. `/glance import` reads your bindings
    again.
  - A key that holds an old spell rank (you know a higher one) shows a
    small amber corner, and its tooltip says so. `/glance ranks` puts your
    best known rank on every action slot, out of combat.
  - Glance's keys win over Bartender4's for the same key. Hide the
    Bartender bars you no longer need in Bartender's options.
- **Unit frames**: small player and target bars under your character and a
  cast bar below them. They replace Blizzard's player, target and cast
  frames (`/glance blizzard on` keeps those).
- **Edge pointers**: arrows on the minimap's rim for things off the map,
  with the name and yards: party members (class colours), your map pin and
  your corpse. Other addons add points with
  `Glance.minimap.addPointerSource(fn)`; `fn()` returns
  `{ { mapID, x, y, r, g, b, label }, ... }` in map coordinates.
- **Edit mode**: the game's Edit Mode (Esc, Edit Mode) also unlocks Glance,
  the same as `/glance edit`: drag the keyboard bar or the minimap to move
  them, and the minimap's gold corner to size it. `/glance reset` puts both
  back.
- **Minimap**: square, top-right, mouse-wheel zoom, right-click for
  tracking. Drag the gold corner at its bottom left (it shows when the
  mouse is over the map) to resize it, hold Shift and turn the mouse wheel
  over it, or type `/glance map 250` (120 to 400). The zone, coordinates and clock are under it, and the
  LibDBIcon addon buttons (Questie, Details and the rest) are in one
  drawer behind the Addons tab. A Reload button sits under it, then amber chips show what you can spend
  or fix: unspent talent points, Legacy points, keys with an old spell rank
  and your free bag slots (always shown, amber at 2 or fewer). A green XP chip shows your XP buff and its time left (hover
  for every XP buff and your rested XP); it turns amber, "No XP buff", when
  none is on. Then a message in the middle of the screen reminds you, at
  login, when a buff runs out and every 10 minutes (not in combat or
  instances). `/glance xpremind off` stops the reminder. Glance finds an XP
  buff by "experience" or "XP" in its name, spell text or tooltip. If it
  misses one, click the XP chip and tick the buff (or `/glance xpbuff NAME`);
  the mark is kept for all your characters. Click one to open that window; it hides when done.
- **Enemy cast bar**: when your target casts, a bar with the spell
  name shows just above your unit frames. Orange when it can be
  interrupted, grey when not; "COUNTERSPELL" and a gold edge while your
  Counterspell is ready (from the watch row), and a grey "Counterspell 12s"
  while it cools down. In combat, click the bar or
  the call-out to cast your interrupt (Counterspell, Kick, Pummel or Earth
  Shock) on your target. The click area stays there in combat while you
  target a living enemy, even between casts, because the game does not let
  addons show or hide a spell button in combat.
- **Watch row**: your key spells (for a mage: Blink, Counterspell, Frost
  Nova, Ice Block, Cold Snap, Ice Barrier, Evocation) as large icons below
  the cast bar. Bright when ready, dark with a sweep on cooldown, a short
  flash when one comes back. `/glance watch add NAME`, `remove NAME`,
  `reset`. Only spells you know show. Click an icon to cast it.
- **Range**: the target frame gets a green edge while your longest-range
  spell reaches the target, red when it does not. Under it is the
  distance: exact yards for a party or raid member ("23 yd"), and for
  anyone else a bracket from your spellbook's ranges and, out of combat,
  the interact distances ("20-28 yd"). The game gives addons no position
  for other units, so an exact number is not possible there.
- **Party**: in a group, each party member gets a large class-coloured
  name above their nameplate, and friendly player nameplates are on.
  Your own nameplate settings come back when you leave the group.
  `/glance party off` turns it off.
- **Old bars**: `/glance bars hide` hides Bartender4's bottom action bars
  (1, 2 and 5-10; the right-edge bars 3 and 4 stay),
  Blizzard's bottom bars, the gryphon art and the old XP bar, and draws a
  thin XP bar along the bottom edge, with your XP, the percentage and rested XP in it
  ("12,345 / 20,000 (61.7%)  Rested 15%"). The bag bar, micro menu, pet and
  stance bars stay. Move click-only items (food, potions) onto Glance keys
  first. `/glance bars show` brings everything back.
- **Chat**: Blizzard's chat in the same look: a faint panel, tabs that show
  under the mouse, no side buttons, a plain edit box, and text that fades
  after 30 quiet seconds (scroll or hover brings it back).
- `/glance keybar off`, `/glance units off`, `/glance minimap off` and
  `/glance chat off` turn a part off (the game reloads).

The bar uses the game's secure action buttons and override bindings
(`SetOverrideBindingClick`), so it only reads bindings; it never changes
your saved Key Bindings.

## Forever client notes

- A secure button (a click that casts) works only when it is registered
  for `AnyDown` with the attribute `pressAndHoldAction` set to true, as
  Blizzard's own Forever buttons do. `/cast [@Name]` does not reach
  players outside your group: target them by name, cast, then
  `/targetlasttarget`. `UnitName` gives the surname as its second value:
  `/target First Surname` finds the player.
- In combat, aura names (and times) are secret, even your own. BuffCheck
  keeps the last full read of each unit and counts its buffs as on until
  their end time; a buff removed early in a fight still shows until then.
- The `UNIT_AURA` payload can be secret: reading `info.addedAuras` or
  `info.isFullUpdate` raises "table expected, got secret". Do not read
  it; rescan the unit's auras with `C_UnitAuras.GetAuraDataByIndex`
  and pass each value through `issecretvalue` first.
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
- Forever has the newer "secret values": `UnitHealth` always, and
  `UnitPowerMax`, `UnitLevel`, cast times and cooldowns at times, come back
  hidden. Pass them straight to a status bar or `SetText`; any compare or
  sum on one is an error ("attempt to compare ... a secret number value").
  Test with `issecretvalue(v)` first. A cast bar runs on
  `StatusBar:SetTimerDuration(UnitCastingDuration("player"))`.
- `Cooldown:SetCooldown` is a protected function. On a cooldown frame that
  is a child of a secure button, addon code cannot set it (no sweep shows).
  Put the cooldown on a plain frame laid over the button.
- A secure button's modified attribute needs its button part:
  `shift-action1` (or `shift-action*`). A bare `shift-action` is never read,
  so Shift+key fired the unmodified action.
- Health (and sometimes power) is secret, but `AbbreviateLargeNumbers` takes
  secret values and the result can be joined into a string for `SetText`.
  Wrap it in `pcall` and fall back to the bare value.
- `UnitDistanceSquared` works only for party and raid members. For any
  other unit, bracket the distance with `C_Spell.IsSpellInRange` over the
  spellbook and `CheckInteractDistance` (out of combat).
- Do not rely on modified attributes for a Shift+key binding. The game reads
  Shift again when it runs the click (on key up, unless
  `ActionButtonUseKeyDown` is on), so a Shift let go early fires the plain
  action. Bind `SHIFT-<key>` to its own hidden secure button instead, and
  set the override bindings with priority: Bartender4 keeps its own override
  bindings on the number keys while its bars are hidden.

## Develop

Checks, from the repo root (Lua 5.1 and Python 3):

| Check | What |
| --- | --- |
| `lua5.1 tests/lootvalue.lua` | LootValue against a mock of the game and Auctionator APIs |
| `lua5.1 tests/omni.lua` | Omni against a mock of the game API |
| `lua5.1 tests/upgradefinder.lua` | UpgradeFinder against a mock of the game API |
| `lua5.1 tests/questboard.lua` | QuestBoard against a mock of the game API and Questie |
| `lua5.1 tests/buffcheck.lua` | BuffCheck against a mock of the game API |
| `python3 -m unittest tests/test_release.py` | Zips, manifest, version guard, changelog, page |

The `tests` workflow runs all six on each push and pull request. The real
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

**Spare files: no restart for a new file.** The client reads each `.toc`
only when it starts, so a `.lua` file that the `.toc` does not list yet
needs a full restart. Each addon's `.toc` therefore ends with empty
`Spare1.lua` to `Spare5.lua` files. Put new code in the next free spare and
it loads with `/reload`. The spares load last, after the addon's other
files. Before a release you can rename a used spare to a real name and add
a new empty spare in its place; that one change needs one restart. Keep at
least one spare in every `.toc` (a test checks it), and give a new addon
its spares from the start. A brand-new addon folder still needs a restart.

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
