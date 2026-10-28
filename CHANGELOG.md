# Changelog

All notable changes to Fish Breeder Job Simulator. Newest first.

## [0.5.1] - 2026-10-28

### Changed
- **Albino is now a mutation-only prize**, like Glass. It's no longer sold in
  the Market; the only way to get one is a lucky 3% mutation when breeding.

## [0.5.0] - 2026-10-28

### Added
- **Closed for restock** (playtesting aid): the **Restock** button in the top
  bar closes the shop to customers and runs the clock **4× faster**, so broods
  and fry growth build up stock quickly. Anyone waiting at the counter leaves
  with no penalty. It stays on across days until you press **Reopen**; the
  clock shows "×4" while it's on. Set `clock.restock_speed` to 0 in
  `data/economy.json` to remove the button.

## [0.4.1] - 2026-10-28

### Added
- Each breeding tank's tab in the back room now has a small list of what's in
  it (e.g. "♂ Red ★★, ♀ Yellow ★★, + 2 fry"), so you can see every tank at
  a glance without switching tabs.

## [0.4.0] - 2026-10-28

### Added
- **See your profit or loss before you sell.** When a customer wants one of
  your fish, the counter shows what you paid and what they'll pay, e.g.
  "You paid $39 · Priya will pay $30 (a $9 loss)". Fish you bred cost nothing.
- **Breed one for them.** If selling would be a loss, a **Breed one** button
  lets you keep your fish (to breed from) and promise the customer one like it
  (same variety and sex) at the quoted price. They come back in 2–3 days; hand
  it over from **Back-orders** once you've bred a matching adult. The fish you
  kept and your breeding pairs are never handed over, and there's no penalty
  if you're late.
- Fish lists show what you paid for each fish and what customers pay for it.

### Fixed
- The confirmation message after **Order it in** now shows at the counter.

## [0.3.0] - 2026-10-28

### Added
- **Up to 4 breeding tanks.** You start with one; buy more from the back room
  with **+ Add tank** ($75, $100, $150). Each tank is completely separate: fish
  only breed with others in the same tank, so different lines never mix. Each
  tank has its own brood countdown, and each tank with fry uses its own fish food.
- Back room tabs (Tank 1–4) to switch the big view between breeding tanks.
- **Move ▾** menu on every fish (back room and shop floor) listing the display
  tank, each breeding tank you own, and holding. Places a fish can't go are
  greyed out, with the reason.
- **Market tabs:** Fish, Decorations (plants, rocks, driftwood, decor) and
  Supplies (tanks, fish food, substrate).

### Changed
- The clock runs 25% faster: an in-game hour is now 48 real seconds (was 60),
  so the shortest day is about 3 minutes.
- The end-of-day summary lists the brood outlook for every breeding tank.

### Fixed
- Fish in the back room no longer start bunched in one corner of the tank.

## [0.2.0] - 2026-10-28

### Added
- **Plant and rock art:** all 45 plants, rocks, driftwood and decorations now
  come from the aquascape sprite sheet: 29 plants (tall, medium and carpeting),
  10 rocks and pebble piles, 3 driftwood and 3 decorations (Coconut Hut, Clay
  Pot, Ruined Arch). They show as pictures in the tank, on the shelf, in the
  Market and in the tank editor.
- itch.io cover image and screenshots (`docs/images`), rendered from the game's
  own art by `tools/make_thumbnail.gd` and `tools/capture_screenshots.gd`.
- This changelog and a full README.

### Changed
- The starter display tank now uses Vallisneria, Java Fern and Slate Stack.
- `tools/cut_sheet.gd` replaces the guppy-only sheet tool. It can cut any
  sprite sheet, and "repack" sprites that sit too close together.

### Fixed
- Slivers of neighbouring plants no longer show around some items.
- The tank editor no longer spills off the screen with long item names.
- Wide plants in the edge spots stay inside the glass.
- Fish added to a tank no longer bunch up against one side at first.

## [0.1.0] - 2026-10-27

First playable version, published to itch.io as a web build.

### Added
- **Shop and day cycle:** shop floor with a display tank, retail shelf and
  counter; a clock (close after 4 hours, or stay open until 21:00); an
  end-of-day summary of sales, customers, new fry and mutations.
- **Breeding:** a back-room breeding tank; fry grow over 3 days if fed and
  reveal 1–5 star quality; 24 guppy varieties from the guppy sprite sheet,
  15 mixing recipes and 2 mutation-only varieties.
- **Customers:** walk-ins arrive more often the better your fish are. They buy
  fish, shelf items or whole tanks; some bring requests (built and delivered for
  a bonus), and some can be back-ordered at 10% off.
- **Market:** named guppy strains in four price tiers, plus supplies.
- **Tank editor:** a substrate slot and six placement slots with a live looks
  score, breakdown and tips.
- **Selling:** to customers, or to the wholesaler for less (fry too).
- **Shop bell:** rings when a customer arrives while you're in the back room.
- Pure, data-driven game logic with 167 headless unit tests.
- Web export for itch.io and a one-command publish script.
