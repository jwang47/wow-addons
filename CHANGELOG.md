# Changelog

Each release raises `## Version` in the addon's `.toc` and
adds a section here, newest first. `tools/release.py check` refuses an
addon whose files changed since the live release while its version stayed
the same, and a test checks that every `.toc` version has a section here.

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
