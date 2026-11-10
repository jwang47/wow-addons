# Changelog

Each release raises `## Version` in the addon's `.toc` and
adds a section here, newest first. `tools/release.py check` refuses an
addon whose files changed since the live release while its version stayed
the same, and a test checks that every `.toc` version has a section here.

## UpgradeFinder 0.2.0

- New: crafting lines on recipes. Hover a pattern or other recipe item, or
  a recipe in your profession window, to see the cost to craft, what the
  made item sells for (AH, vendor or disenchant), the profit or loss, and
  the score of the made item against what you wear. `/uf craft` turns them
  off.
- Hovering a row in the profession window's recipe list now shows the made
  item's tooltip.
- Transformations: the tooltip of a material you can make into another
  item (Silk Cloth into Bolt of Silk Cloth, ore into bars) says what one
  craft gains or loses ("Make into Bolt of Silk Cloth (4 each)").
- Reagents the client has not seen yet get their AH price too: UpgradeFinder
  learns the item names in the Auctionator scan once and saves them.

## LootValue 0.2.1

- The AH scan time on the tooltip says "AH full scan 3h ago".
- An item that today's full scan did not see says "not in today's full
  scan" instead of yesterday's listings and price trend.
- On a pattern or other recipe, the line prices the recipe itself. Before,
  it priced the item the recipe makes (the game reports that item on a
  recipe tooltip), so a pattern showed a disenchant value.

## Omni 0.1.3

- The item tooltip says "AH full scan 3h ago" like LootValue, and "not in
  today's full scan" next to an old price.

## QuestBoard 0.2.0

- Cleaner quest rows. Line 1: the name and how far. Line 2: what to do,
  and at the right the same two numbers on every quest ("625 xp  3 min",
  coloured by XP per minute; "~" is a guess). A gear line comes only when
  there is gear: "Reward: [Rose Mantle]" or "Leads to [Seal of Wrynn],
  4 quests on", in place of "chain +4 ->".
- A calmer top: no "Quests / level" title line (the tabs are the top), no
  count on the Log tab, no group name that repeats the tab, and the group
  hints ("within 300 yd") moved into the group's tooltip.
- Fix: a Lua error ("Items.lua:60: table index is nil") when a pinned
  quest that starts from an item was on the board.
- Fix: a level with a tag ("33G") no longer wraps and pushes the name
  down over the line under it. A what-to-do line that is too long for the
  board goes on to a second line in place of being cut.
- More space between quests than between the lines of one quest, and
  space above the progress bar. The "XP only" line is gone (the tooltip
  still says it); a chain shows only when it ends in gear.
- Fix: pins stay after a /reload or a login. A pin goes only when you
  hand the quest in.
- A quest that starts from a world drop (Questie does not know where the
  item drops) is no longer offered as a pick-up: you cannot go and get it.
  A pin keeps it, marked "drop unknown", and its tooltip says "Hand in to"
  in place of "Get it from".
- Dungeon and raid quests that the game does not tag (most Classic ones,
  like The Fury Runs Deep) now get their D or R: Questie files them under
  the dungeon. Their time is a run (about 45 min for a dungeon, 2 h for a
  raid, less the part you have done), not a few kills, so XP per minute is
  real.
- New layout: four tabs for what you are doing, in place of nine groups.
  Doing (picked by itself while a quest is Active): the quests you are on,
  the stops on the way, your party, and one line that counts the rest of
  your log. Nearby (picked by itself otherwise): one list of what to chain
  next within 1000 yd, best XP per minute with the walk counted, hand-ins,
  objectives, pick-ups and areas mixed. Areas: zones to go to or swap to,
  by XP per minute with the trip counted, far ones after; and the nearest
  inn and flight master. Log: every quest in your log by zone, never cut.
  A click on a tab keeps it until you start or finish a quest. The "Next:"
  line is gone: the first row of Nearby is the suggestion.
- A log quest with no known place says "no place".
- A quest you finish stays in Doing as a hand-in (pinned until you hand it
  in; else for 10 minutes after your last progress), so the next step,
  taking it back, is on top. Your pins also sit in a "Pinned" list at the
  top of the Nearby, Areas and Log tabs.
- Alt-click a list's heading (Chain next, On the way, a Log zone) to pin
  every quest you see in it, the stops of its areas too; they all go to
  Doing. Alt-click again to unpin them. Alt-click a zone in Areas pins
  every quest there, far pick-ups too.
- The grip at the bottom right now sets the width too (drag it sideways,
  220 to 560, or `/qb width N`). While you drag, a gold outline shows the
  max size and its numbers, so you see the limit even when the board is
  shorter.
- Dungeon, raid and group quests have a tag after the level: 28D, 40R,
  22G (the game's quest tag, else Questie's, else the group size).
  `/qb dungeons off` keeps dungeon and raid quests to the Log tab and
  leaves their pick-ups out; `/qb dungeons on` brings them back.
- Quests over your level count slower in time left and XP per minute:
  1.25x at +1, 1.6x at +2, 2.2x at +3, 3.2x at +4, 6x at +5 or more (red,
  hard alone); 3 or more under, 0.85x. Once you make progress on a quest,
  your measured pace on it counts instead. The tooltip says when a quest
  is counted slower.

- Alt-click pins any quest, not only the ones you are working on: a
  hand-in or a pick-up goes to Active with a gold star too. A pinned
  pick-up stays pinned when you take it; a pin goes when you hand the
  quest in. Alt-click on an area pins its hand-ins and pick-ups as well.
- The tooltip of each quest shows its whole chain (with Questie): "Chain:
  quest 3 of 5", then each step with its level, marked done, ">>" (this
  quest), log (in your log) or "..." (later). A long chain shows the 8
  steps around this quest.
- A "Your party" group: one row per party member with their level (in
  their class colour), how they are (offline, dead, AFK, health), how far
  and which way (or their zone), and how many of your quests they share
  and how many they are behind on. Point at a row for their progress on
  each shared quest; click pins where they are on the map. `/qb party off`
  hides it.
- A group with more quests than its rows no longer drops the rest without
  a word: its head says "8 of 12", and a last "+4 more: ..." line names
  them. Click that line for the whole group ("show fewer" folds it).
- `/qb why NAME` says where a quest is on the board, or why it is not
  there (row limit, level, far away, a pre-quest first, or not in
  Questie's data).

## GroupUp 0.1.0

- New: a panel that helps you decide whether to group up (`/gu`). It
  shows which quests in your log a group speeds up, your measured XP per
  hour solo and in each group size at about your level, and how kill XP is
  split in a group. When someone invites you, two summary lines go to chat.
- A "Thanks & leave" button while you are in a group (`/gu bye`): it thanks
  the party in chat and leaves 5 seconds later.

## Niceties 0.1.0

- New: a home for small nice-to-haves (`/nice`). The first one zooms the
  camera out as far as the game allows (`/nice zoom` toggles it).

## Glance 0.1.0

- New addon, a lighter HUD (`/glance`). Not in the releases yet: try it
  with `dev.ps1 Glance`.
- An enemy cast bar near your character, with a COUNTERSPELL call-out
  while you can interrupt and the cooldown left while you cannot. Click it
  in combat to interrupt.
- A watch row of key spells (Blink, Counterspell ...) under your character.
  Click an icon to cast it.
- Range on the target frame: a green or red edge, exact yards for party
  members and a yard bracket for anyone else.
- Party members are easy to find: a large class-coloured name above each
  one's nameplate while you are in a group (`/glance party off`).
- Edge pointers on the minimap for party members, your map pin and your
  corpse when they are off the map; addons can add their own.
- The game's Edit Mode unlocks Glance too: move the bar and the minimap,
  size the minimap.
- A Reload button under the minimap.
- An XP buff chip: time left, rested XP on hover, and a reminder in the
  middle of the screen when no XP buff is on (`/glance xpremind off`).
  It reads the buff tooltip too, and a click on the chip lets you mark a
  buff it missed (`/glance xpbuff NAME`).
- Alerts under the minimap: unspent talents, Legacy points, old ranks and
  free bag slots, each a chip that opens the window.
- Old spell ranks: an amber corner on the key, and `/glance ranks` swaps
  in your best rank.
- A keyboard bar: one button per key of the left hand (1-6, Tab Q W E R T,
  A S D F G, Z X), laid out like the keyboard. At the first login it
  reads your key bindings, so each spell shows on the key it is already on.
  Movement keys and keys with other commands stay as they are. Drag a spell
  onto a key to put it there; hold Shift to see and fill the Shift layer.
  Drag a spell between keys to move or swap it (`/glance lock` makes that
  need Alt). `/glance take all` puts
  every key with another command (except Tab, the bag keys and the character pane) on the bar. In edit mode the
  bar can be dragged to another place (`/glance reset` puts it back).
- Small player and target bars under your character (health and mana as
  numbers), and a cast bar below them. They hide Blizzard's player, target and cast frames
  (`/glance blizzard on` brings those back).
- A square minimap in the top-right corner: mouse-wheel zoom, the zone,
  coordinates and clock under it, and the addon buttons in one drawer.
  Drag the gold corner, use Shift+mouse wheel or type `/glance map SIZE` to resize it.
- `/glance bars hide`: hides the Bartender4 bottom bars (the right-edge
  bars 3 and 4 stay) and Blizzard's bottom bars, the
  gryphon art and the old XP bar (a thin XP bar with the numbers and
  the percentage in it replaces it).
- Chat in the same look: faint panel, tabs only under the mouse, no side
  buttons, text fades after 30 quiet seconds.
- Shift layer and cooldown sweeps work in the game (first test round).
- Works with the client's hidden (secret) health, power and cast values.

## LootValue 0.2.0

- The AddOns list names it "LootValue: Sell, Vendor or Disenchant", so it
  says what it does.
- Auto-loot that leaves cheap junk on the body. It always takes money,
  quest items, green or better items, cloth and other materials,
  consumables, recipes, bags and keys. It takes other items only when
  they are worth at least 10c a character level (vendor, AH or
  disenchant, times the stack), or when they fit on a stack you carry.
- The loot window stays open on what it left, so you can click an item to
  take it after all (`/lv autoloot quiet` closes it and prints one chat
  line instead). Shift+loot takes everything. `/lv skipped` lists the last
  items it left. `/lv autoloot off` turns it off.
- It turns off the game's own Auto Loot while it is on, and puts it back
  when you turn it off.

## Omni 0.1.2

- The AddOns list names it "Omni: Search Everything".
- Search dungeons by name or short name ("bfd", "sm gy"). The row shows
  the levels, the short name and the boss count.
- Enter on a dungeon (or `loot: bfd`) lists each boss's drops, then the
  dungeon's quests and their reward items (with Questie). Hover an item
  for its tooltip; Enter links it.
- Enter on an item shows where to get it (with Questie): the mobs that
  drop it, the objects that hold it and the vendors that sell it, nearest
  first, with yards on your map or the zone. Enter on one pins it on the
  map. Shift+Enter links the item.
  When Questie lists a source but has no location for it (some Forever
  quests), a row says so, and the quests that need the item follow. An
  empty `from:` view says why (no such item, no source, Questie loading).

## QuestBoard 0.1.1

- XP colours: in each group, the best third of the XP (Turn in) or XP per
  minute (Pick up, Party has, Areas) is green and the worst third grey.
- Clearer grouping: a quest's two lines sit closer, quests have a small gap
  between them, and each group name is gold with a thin rule under it and
  more space above it.
- Town group: the nearest innkeeper and flight master of your side, with
  distance and arrow. Click (or `/qb town`) pins it on the map.
- Active quests show a line per open objective, your party's progress
  on it and where the chain leads (up to 5 lines).
- Areas count only real stops: no item-started pick-ups (their place is a
  drop or the finisher) and no party quests you cannot take. Inside an
  area its name says "Around you", and Next no longer says to go there.
- A quest you are not done with points to where you get its items (the
  mob that drops them, the object that holds them or a vendor), found by
  item id or name, never to the turn-in. When Questie does not know the
  source, the row points to where you last made progress on it (saved
  across sessions), or has no distance and the tooltip says so.
- Time estimates count every kill or loot left (27 drops is not 2
  minutes): your measured pace on that quest, else a guess of 30 s each,
  and the tooltip says when it is a guess.
- The Next line (when no quest is Active) picks the step with the best XP
  per minute from where you are, travel included, not a far hand-in.
- `/qb party off` hides party members' quests on the board (Party has,
  "with" and Party lines) and turns off Questie's party objectives on
  the map; `/qb party on` brings both back.
- With Glance loaded, its minimap edge arrows also point to the Next
  quest's place, the nearest hand-in and the inn and flight master.

## QuestBoard 0.1.0

- New addon (`/qb`): a small board of the quests that matter now.
  Groups: Active, Nearby, Areas, Turn in, In your log, Party has, Pick up.
- Each row says what to do next, how far it is (coloured by range) and
  which way. Turn in rows show the XP, the reward item and the run time.
  Pick-ups are sorted by estimated XP per minute; far quests by XP.
- Active quests have a progress bar and the time left at your own kill
  pace. Alt-click pins a quest (gold star); Alt-click an area pins all.
- Click opens the map there, right-click the quest log. Quest items get a
  button beside their quest. Chains say where they lead.
- In combat, in dungeons and while you do a quest, the board shows only
  what helps; point at it to see everything. Drag to move it; drag the
  corner grip to set its max height and scroll for the rest.

## BuffCheck 0.1.0

- New addon: your buffs and your group's in a small grid (`/buffs`).
  Green on, yellow ending (minutes left), red missing. Click a row to buff
  that person. The Next line (and its key binding) buffs whoever needs it
  next, returns the favour to a stranger who buffed you, and offers your
  buff to players near you.
- Scrolls in your bags (stat scrolls and Forever weapon imbues): a Scroll
  column shows the ones you can use whose buff is not on you, and Next
  reads them. Its tooltip says why a scroll is not counted.

## Omni 0.1.1

- Nearby is always the first group in the results.
- With an empty search, Omni shows the 5 nearest NPCs above Recent.

## UpgradeFinder 0.1.9

- The AddOns list names it "UpgradeFinder: Gear Upgrades".
- Chat messages start with "UpgradeFinder:" instead of "Upgrades:".
- Spell damage against one creature type ("damage done to Undead by
  magical spells") is its own stat, not spell damage. The built-in weights
  give it 0; with MageMentor, a mage uses MageMentor's weight (0.1).

## UpgradeFinder 0.1.8

- Fix a Lua error when the Upgrades window opens for the first time
  (`attempt to index field 'slot'`). The new resize corner made the window
  repaint before its buttons existed.

## UpgradeFinder 0.1.7

- The Upgrades window can be resized: drag its bottom-right corner. A
  taller window shows more rows (up to 40). The size is saved.

## UpgradeFinder 0.1.6

- A **Build** window (the Build button on Upgrades, or `/uf build`), in the
  style of Path of Building: your 18 slots on the left and a sheet on the
  right with your totals now, with the build, and the change: health,
  mana, armor, eHP, spell damage or attack power, crit, and for a caster
  DPS, mana per second and time to OOM. Drop an item from your bags on a
  slot, or Alt-click an Upgrades row; right-click a slot goes back to what
  you wear, shift-right-click leaves it empty.
- Save builds by name, load them (the Builds button), and compare the build
  with what you wear or with any saved build (the Compare button).
- The combat log is off by default: the Forever client forbids it to
  addons (a "blocked" pop-up at login). `/uf calib log` turns it on for this session only (never saved). A
  blocked call is now named in chat.
- Caster DPS from your action bars: each damage spell on a bar gives its
  damage (from the spell text, or your measured hits), cast time, cooldown
  and mana. Cooldown spells go whenever ready, the best filler the rest of
  the time. The window shows the rotation; row tooltips use it for Est. DPS
  until the combat log has enough hits.
- Patterns, plans and other recipes on the AH now show as the item they
  make (tagged "craft"), scored like any other item. A missing profession
  does not hide them; the tooltip names it.
- Craft or buy: a recipe row's price is the pattern plus the reagents
  (AH price, or the vendor's when lower). Its tooltip lists each reagent
  and the made item's AH price, marked "cheaper" when buying it made
  costs less, or "binds on pickup" when you can only craft it.
- The row tooltip is easier to read: one stat per line, the name on the
  left; on the right the item's own number, then the change against what
  you wear in brackets ("+14  (+4)"). Offense and Defense show changes.
- Each weight preset has an x button that deletes it.

## UpgradeFinder 0.1.5

- Calibration: UpgradeFinder measures the Forever formulas from your own
  client. It saves your stats next to the crit, health and mana the game
  reports when your gear, level or stats change, and fits Int per 1% spell
  crit, Agi per 1% crit, health per Stamina and mana per Intellect. From the
  combat log it learns each of your spells: average hit, crit rate, share of
  your damage, and the spell damage coefficient. Measured values replace the
  Classic guesses in the tooltip once there is enough data.
- `/uf calib` shows what it has measured; `/uf calib reset` clears it.
- The Defense line shows **eHP**: effective health against physical hits,
  health / (1 - armor reduction), with the change in percent.

## UpgradeFinder 0.1.4

- A row's tooltip shows what the upgrade changes, in the style of Path of
  Building: the stat changes against the item(s) it replaces, then
  **Offense** (spell damage or healing, spell crit, attack power, crit,
  hit, weapon DPS, and an estimated DPS or healing change) and **Defense**
  (health, armor with the change in damage taken, defense, block, mana,
  mp5). Gains are green, losses red. The derived numbers are estimates.

## UpgradeFinder 0.1.3

- Dungeon drops are candidates too: the boss and trash loot of the 25
  Classic dungeons, Ragefire Chasm to Stratholme. A dungeon row shows the
  dungeon's short name (DM, SFK, BRD...) where an AH row shows the price,
  and its tooltip names the boss and the level range. An AH item that also
  drops in a dungeon gets the same line.
- A fifth button filters the source: All sources, AH only, Dungeons, Bags
  only. `/uf dungeons` turns the dungeon drops off and on.
- The window is 44 px wider for the new button.

## UpgradeFinder 0.1.2

- A **Weights** panel (the Weights button on the window, or `/uf config`):
  one box per stat (gold when changed from the default; empty a box for the
  default), a preset name box with Save and Defaults, and a button per
  preset (click loads, shift-right-click deletes).
- Weight presets: `/uf save NAME` keeps your weights, `/uf load NAME` brings
  them back, `/uf presets` lists them and `/uf delete NAME` removes one.
- `/uf weight STAT default` undoes one stat; `/uf weight reset` goes back to
  the defaults for your spec. An unknown stat name is refused, with the list.
- A weight change scores the items again at once when the window is open;
  the title shows the preset name or "custom".

## UpgradeFinder 0.1.1

- Each row shows the item's slot (Chest, Ring, Ranged...) between the name
  and the gain. The window is 60 px wider for it.

## LootValue 0.1.0

First release. Needs Auctionator (run a Full Scan at the Auction House now
and then).

- One tooltip line on each item: sell it on the Auction House, disenchant it
  or sell it to a vendor, from Auctionator's prices.
- The AH comes first only when, after the 5% cut and the deposit you lose if
  it does not sell, it pays 1.5x the best sure option and 1s more (2x when
  the market looks slow: 50+ listed, or 50+ full stacks for a trade good; a
  price that fell 10% since the last scan day; or a price 3+ days old).
- With an AH price on the line, it says how old Auctionator's last scan is
  ("AH scan 3h ago").
- Disenchant values come from the Classic disenchant table and the AH prices
  of the materials, because Auctionator has none on Forever.
- A soulbound item gets no AH option.

## Omni 0.1.0

First release. Works alone; Questie, Auctionator and MageMentor add more
results.

- One search box: Ctrl+Space or `/omni`. `/omni bind KEY` sets another key.
- Results: your items (bags, bank, mail, the Auctionator scan), places on
  the map, people (friends, guild, group, recent whispers), spells, your
  quest log, nearby Questie NPCs with yards, and Questie NPCs and quests.
- Enter acts (link an item, open the map, whisper, put a spell on the
  cursor, pin an NPC on the map); Shift+Enter or a right click does the
  second action.
- Filters such as `i:` items, `p:` places, `@` people, `q:` quests and
  `near:` nearby NPCs. Fuzzy matching finds skipped letters and one typo.
- Typing searches run in slices with a 4 ms target per frame.
- Item rows show how old the AH price is ("today", "3d old"), and the item
  tooltip adds the last AH scan time ("AH scan 2h ago").

## UpgradeFinder 0.1.0

First release. Any class. Works alone; Auctionator adds AH items,
Questie adds where to get them, and MageMentor's weights are used for a mage.

- `/uf`, a key binding or the **Upgrades** button on the Auction House opens
  a short list of gear from your Auctionator scan and your bags that beats
  what you wear, biggest gain first.
- Buttons pick the slot, usable now or up to 2 levels ahead, biggest gain or
  gain per gold, and any price or what you can afford.
- Scores use simple leveling weights for your spec (the talent tree with the
  most points). `/uf weight STAT N` changes a weight.
- The scan reads items in slices and asks the server for unloaded items in
  batches; scores are saved, so a /reload shows the list at once.
- With Questie, rows and gear tooltips say where to get an item: a quest
  reward, a dungeon, a vendor or a drop.
