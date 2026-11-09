# Changelog

Each release raises `## Version` in the addon's `.toc` and
adds a section here, newest first. `tools/release.py check` refuses an
addon whose files changed since the live release while its version stayed
the same, and a test checks that every `.toc` version has a section here.

## Glance 0.1.0

- New addon, a lighter HUD (`/glance`). Not in the releases yet: try it
  with `dev.ps1 Glance`.
- A keyboard bar: one button per key of the left hand (1-6, Tab Q W E R T,
  A S D F G, Z X), laid out like the keyboard. At the first login it
  reads your key bindings, so each spell shows on the key it is already on.
  Movement keys and keys with other commands stay as they are. Drag a spell
  onto a key to put it there; hold Shift to see and fill the Shift layer.
  Drag a spell between keys to move or swap it (`/glance lock` makes that
  need Alt). `/glance take all` puts
  every key with another command (except Tab, the bag keys and the character pane) on the bar. In edit mode the
  bar can be dragged to another place (`/glance reset` puts it back).
- Small player and target bars under your character, and a cast bar below
  them. They hide Blizzard's player, target and cast frames
  (`/glance blizzard on` brings those back).
- A square minimap in the top-right corner: mouse-wheel zoom, the zone,
  coordinates and clock under it, and the addon buttons in one drawer.
  Drag the gold corner (it shows on mouse-over) or type `/glance map SIZE` to resize it.
- `/glance bars hide`: hides the Bartender4 bottom bars (the right-edge
  bars 3 and 4 stay) and Blizzard's bottom bars, the
  gryphon art and the old XP bar (a thin XP line replaces it).
- Chat in the same look: faint panel, tabs only under the mouse, no side
  buttons, text fades after 30 quiet seconds.
- Shift layer and cooldown sweeps work in the game (first test round).
- Works with the client's hidden (secret) health, power and cast values.

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
