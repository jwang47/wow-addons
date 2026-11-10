# Changelog

Each release raises `## Version` in the addon's `.toc` and
adds a section here, newest first. `tools/release.py check` refuses an
addon whose files changed since the live release while its version stayed
the same, and a test checks that every `.toc` version has a section here.

## LootValue 0.2.0

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

## Omni 0.1.1

- Nearby is always the first group in the results.
- With an empty search, Omni shows the 5 nearest NPCs above Recent.

## UpgradeFinder 0.1.9

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
