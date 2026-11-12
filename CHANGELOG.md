# Changelog

All notable changes to Fish Breeder Job Simulator. Newest first.

## [0.22.1] - 2026-11-11

### Fixed
- The top menu bar and the back room's tank tab row no longer get cut off
  in a narrow window. Both now wrap onto a second line when they run out of
  room.

## [0.22.0] - 2026-11-11

### Changed (balance, from a 100-day bot test)
- **Selling the display tank** now pays the tank's Market build cost plus 6%,
  plus up to 6% more for great looks, with any fish at their own prices.
  Before, a decorated tank could sell for nearly three times what it cost, so
  selling and rebuilding it was a money loop.
- **Shop items** now sell to customers for about 1.25 times their Market cost
  (they were 1.6 to 2 times). Decorations are still worth stocking, but
  buying and reselling them, including with standing orders, is no longer a
  hands-off earner.
- **Special orders** pay a smaller bonus (base reward 60 to 45), and since
  tank values are lower they pay roughly $45 above the fish and materials
  instead of $157. They are still better than selling the same things
  separately.
- Fish prices, collectors, shows and reputation are unchanged.

### Added
- Developer tools `tools/playbot.gd` and `tools/exploit_probes.gd`: a
  headless player that plays 100 days in three styles, and probes for money
  loops. See DESIGN.md.

## [0.21.0] - 2026-11-11

### Added
- **Standing orders (auto-reorder):** a new tab in the Market. For any item
  (fish food, decorations, plants and so on) switch on **Auto**, then set
  "when stock is at or below N" and "order M". The shop pays at the normal
  Market price (no discount) when stock runs low, and the goods arrive the
  next morning. It never reorders while a delivery is already on the way,
  and if you can't afford it, it quietly waits (no debt). A "Keep at least $"
  setting protects your cash. Fish food shows how much your tanks use a
  night. Fish are never auto-ordered.
- A "Delivery" toast each morning, a "Standing orders" block in the day
  summary, and an "Auto-order on" tag on the Supplies and Decorations rows.
- Two new goals ("Never run out", "Well supplied") and Stats lines.

## [0.20.0] - 2026-11-11

### Added
- **Shop staff** (unlock at reputation level 5, "Breeder of Note"): hire up
  to three helpers ($60, $120, $200) at $10 a day each. Open **Staff** from
  the foot of the shop-floor shelf panel. Each helper has one job, and each
  job can only be covered once:
  - **Fish feeder:** if fry would go unfed because you're out of fish food,
    buys a portion at the normal Market price so they keep growing.
  - **Decorator:** hangs spare decorations in empty spots, best-looking first,
    display tank first. It never moves what is already placed and leaves one
    of each item on the shelf for customers.
  - **Stock clerk:** tops fish food up to 5 each night, spending at most $40
    and never dropping you below $50.
- Wages are never a debt: if you can't afford one, it is skipped. Letting
  someone go is free. Wages don't count as negative earnings.
- A "Staff report" in the day summary says what each helper did.
- Three new goals (first hire, full team, 100 jobs done) and a Staff section
  on the Stats tab.

## [0.19.0] - 2026-11-11

### Added
- **The Gallery** (button in the back room): framed portraits of your
  favourite fish, and a **Hall of Fame** of every fish that won a show
  ribbon. Each portrait shows the fish, its name, variety, stars, purity if
  scanned, and its ribbons, in a frame coloured for its best placing. The
  Hall of Fame keeps winners even after you sell them.
- **Gallery wall:** at reputation level 6 ("Regional Legend") you can pin up
  to six portraits. They hang as small framed pictures at the foot of the
  shop-floor shelf panel; click one to open the Gallery.
- Three new goals (3 Hall of Fame portraits, first pin, full wall) and Stats
  lines for Hall of Fame portraits and portraits on the wall.

## [0.18.0] - 2026-11-11

### Added
- **Fish shows** (unlock at reputation level 4, "Hobbyists' Choice"): a show
  is judged at the end of every 7th day. Open **Fish Show** in the back room,
  see the class and prizes, and enter one adult fish. Classes rotate: Open,
  Quality (3★+), Rare Colours, Oddity (mutations) and Pure Line (scanned 70%+).
  Every 4th show is a **Grand Show** with double prizes and tougher rivals.
- Judging is overnight against five rival entries. Your fish's score comes
  from its stars, how valuable its variety is, its hidden purity and a little
  judge's luck. Places 1 to 3 earn **ribbons** (blue, red, yellow) shown as
  chips on the fish's cards, cash prizes ($75 / $40 / $20, doubled at a Grand
  Show) and reputation. Skipping a show, or placing outside the top three,
  costs nothing. If the entered fish is sold, the entry quietly lapses.
- Each ribbon win saves a snapshot of the fish in your show history, ready for
  the gallery in a later update.
- Day summary "Fish show results" with the top rivals; a morning reminder on
  show day; hints (Long shot / Good chance / Looks promising) for each entry.
- Five new goals (first show, first ribbon, blue ribbon, five ribbons, Grand
  champion) and a Fish shows section on the Stats tab.

## [0.17.0] - 2026-11-11

### Added
- **Line purity:** every fish now has a hidden purity score (0-100) for its
  line. Breeding a variety true (both parents match the fry) raises it by 8;
  an outcross (the fry matches only one parent) lowers it by 12; a new
  recipe or mutation starts a fresh line at 30. Bought fish and your starting
  pair begin at 50. Old saves give existing fish 50.
- **Purity helps stars:** a purer line shifts the star roll when fry grow up
  (a little at 70+, more at 90+). Fed fry, parent stars and food upgrades all
  still matter, and purity is never the only way to reach 5 stars.
- **The Lab** (unlocks at reputation level 3, "Known in Town"): open it from
  the back room and pay $20 to scan an adult fish. A scan reveals its purity,
  its tier (Mixed, Developing, Pure Line, Champion Line) and, for fish bred
  in your shop, a **Certified** price bonus: +10% at 70+ purity, +25% at 90+.
  Bought fish never get the bonus, so scanning is no resale trick.
- Purity lines on fish cards ("Purity ?" until scanned), and Stats lines for
  fish scanned and purest fish.
- Four new goals: first scan, a Pure Line, a Champion Line and 10 scans.

## [0.16.0] - 2026-11-11

### Added
- **Shop reputation:** a shop-wide score that only ever goes up. You earn
  points for counter sales (more for higher stars), delivered special orders,
  back-orders, collector sales, goals, and first-time recipe and mutation
  discoveries. Buying earns nothing, so there is no money loop.
- **Seven reputation levels**, from Corner Tank up to Famous Fish Shop. Each
  level makes customers arrive more often (+8% per step) and two of them
  allow one more special order. Levels also unlock features that later
  updates add: the Lab, fish shows, hiring staff and the gallery wall.
- A "★ Lv N" chip in the top bar, a level toast, a reputation line (and a
  level-up line) in the day summary, a progress bar in the Goals window, and
  a new **Perks** tab listing what each level gives.
- Three new goals for reaching levels 3, 5 and 7. Older saves are credited
  with points for the sales and orders they already made.

## [0.15.0] - 2026-11-11

### Added
- **Fish names:** give any fish (fry too) a name, up to 16 characters, with
  the **Name** / **Rename** button on its card in the back room or on the shop
  floor. Names show in tank lists, the day summary and your records
  ("Bubbles (Gold Guppy)").
- **Favourites:** mark up to 24 fish with **♥ Favourite**. A favourite is a
  keeper: customers never buy it and it is never handed over to a back-order,
  collector or special order, and it adds nothing to a tank's sale price. It
  still breeds and can sit in the display tank. Selling or delivering the
  display tank leaves favourites with you (in holding).
- Two goals, "Pet name" and "Family" (5 favourites), and Stats lines for fish
  named and favourites kept.

## [0.14.0] - 2026-11-11

### Added
- **Harem breeding:** in each breeding tank the first adult male is the
  **sire**, and up to **3 adult females** each have their own brood on brood
  night. Mothers and their fry all count against the tank's capacity, so it
  is a trade-off for tank space. Mixed-variety mothers can give several
  recipes from one tank. The back room tags the sire and the breeding
  mothers, and the brood line shows how many mothers there are.
- **Stats tab** in the Goals window: Shop, Fish, Orders and stock, and
  Progress. New records with what and when: **biggest sale**, **rarest fish
  sold** and **best fish bred**. New counters: wholesale sales, shelf items
  and tanks sold, customers who wandered off, total spent, fry grown up.
- **New-game screen**, shown when there is no save or after "Start a new
  game":
  - Starting pair: Red & Yellow, Blue & Grass, Black & White, or Surprise me
    (two random common varieties).
  - Mode: **Standard**; **Homegrown** (the Market stops selling fish after
    Day 3); **Shoestring** (start with $40); **Oddity Shop** (mutations are
    five times as common, but customers at the counter only buy mutations).
  The mode and starting pair are saved and shown on the Stats tab.

### Changed
- A grown-up daughter left in a breeding tank now joins the mothers (if
  there is room under the cap). Breeding-group fish are never handed over
  to a back-order; move one to holding first if you want to sell it.
- Existing tanks with two or more adult females will produce more fry.

## [0.13.0] - 2026-11-11

### Added
- **Third-generation recipes:** five new varieties, each made from two
  varieties you bred yourself: Gold × Sunset → **Phoenix**, Koi × Dalmatian →
  **Calico**, Tuxedo × Neon → **Midnight**, Pastel × Turquoise → **Opal**,
  Leopard × Sunset → **Tiger**. Worth ×2.8 to ×3.4. They use tinted
  placeholder art for now. 20 recipes in all.
- **Breeding book rewards:** every first-time discovery pays cash: $15 / $30 /
  $60 for a first / second / third-generation recipe, $50 for a mutation.
  Finding every recipe of a generation pays a bonus ($50 / $100 / $200).
  Undiscovered cards show their reward; the day summary shows what you earned.
- The breeding book groups recipes by generation, each with its own count.
- **Collectors:** a new customer who only wants show-quality fish **bred in
  your shop**. They pay 1.5× the usual price for a 4★ fish and double for a
  5★. Market-bought fish never qualify (no buy-and-resell loop).
- Three new goals: discover a third-generation recipe, sell to a collector,
  sell 10 fish to collectors. "The whole book" now needs all 20 recipes.

## [0.12.0] - 2026-11-11

### Added
- **Saving.** Your shop is saved at the end of every day and picks up where
  you left off next time (in the browser too). **Start a new game** is at the
  bottom of the Goals window and asks twice before wiping the save. Quitting
  in the middle of a day goes back to that morning.
- **Goals** (top bar): 26 things to aim for, from your first sale to
  completing the breeding book. Each has a progress bar and pays a one-off
  cash reward. A note pops up when you reach one, and the day summary lists
  them. The window also shows a few lifetime numbers (fish sold, best day…).
- **Shop upgrades** (Market → Upgrades): 10 permanent improvements, about
  $2,100 in all.
  - Waiting Bench ($60): customers wait 50% longer.
  - Painted Shop Sign ($90), then Lit Window Display ($240): customers come
    20% and then another 30% more often.
  - Order Desk ($150): 2 more special orders and 3 more back-orders at once.
  - Wholesale Contract ($160): wholesaler pays 50% instead of 40% for adults.
  - Auto-Feeders ($180): fry are fed every night without using fish food.
  - Bigger Breeding Tanks ($200), then Breeding Room Extension ($400): each
    breeding tank holds 4 and then another 4 more fish.
  - Conditioning Food ($300): well-fed fry more often grow up a star better.
  - Tank Heaters ($350): broods come one night sooner.

### Changed
- Top bar spacing tightened to fit the Goals button.

## [0.11.0] - 2026-11-04

### Added
- **Bubbling Treasure Chest** decoration ($14 at the Market, sells for $26).
  It's animated: the lid opens and lets out a stream of bubbles. Place it in
  any tank or sell it from the shelf.
- Animated decor support: items can list `frames`, `fps` and `body_height`
  (the object itself, so rising bubbles don't shrink it).
- `tools/cut_animation.py` cuts an animation strip on a flat dark background
  into a transparent, bottom-aligned frame sheet.

- Every back-room breeding tank has a bubbling **air stone** in the back
  corner (a fixture, so it doesn't take a decor slot).

### Changed
- Breeding tanks in the back room always have a sand floor, so they no longer
  look bottomless.
- `tools/cut_animation.py` ignores JPEG noise and reads the background from
  the image corners.

## [0.10.0] - 2026-11-04

### Added
- **Customers ask for specific guppy varieties** you don't have for sale:
  - **Market varieties** (Normal, Red … Koi, Tuxedo, Neon): get one from the
    Market for them. They pay **10% under the Market price** (you were out of
    stock, so you take the hit) and come back **tomorrow**.
  - **Bred-only varieties** (e.g. Purple, Pink, Gold): only ones whose recipe
    is **unlocked in your breeding book**. You breed one; they pay **double**
    the usual price (a 3★ fish) and come back in **a week**.
  - **Mutations** (Albino, Glass, …) are never requested, because they're
    random. Customers only ask for one if you have it for sale.
  - Accepted wishes go on **Back-orders**. Hand over any adult of the right
    variety and sex from the due day (from holding, display or a breeding tank,
    but never a breeding pair).

### Changed
- Replaces the old "wishes for a Market strain at 10% off" rule. Item
  back-orders (10% off) are unchanged.

## [0.9.0] - 2026-10-28

### Added
- **Orders room** (top bar, shows how many orders you have). Each accepted
  special order gets its own column with the request, and its own **order
  tank** that you build separately from your display tank:
  - **Set up order tank** uses an empty tank from your stock (buy more in the
    Market's Supplies tab).
  - **Edit tank** opens the tank editor on that order's tank, with the
    customer's request at the top and a live payout preview.
  - **Deliver** hands that tank and its fish to the customer.
  - **Cancel order** is still free: a started tank, its decorations and its
    fish all go back to your stock.
- The tank editor has a **Fish** section: add adult fish from holding, the
  display tank or a breeding tank, or send them back to holding.
- Order tanks show up in the Move menu and the back room fish list. Their fish
  are reserved, so walk-in customers can't buy them.

### Changed
- At the counter, each order offers **Build in Orders room** or **Give display
  tank → $X** (delivering your display tank is still an option).

## [0.8.0] - 2026-10-28

### Added
- **Breeding book.** A **Breeding book** button in the back room opens a book of
  every recipe and mutation. Each one stays hidden ("? × ? → ?") until you've
  bred it once; then it shows the parents and the result as fish, the day you
  first bred it, and what it's worth. Undiscovered mutations only show how rare
  they are. Progress is shown at the top (e.g. "Recipes 3/15 · Mutations 1/6").
  Buying a fish doesn't count; only breeding does.
- The end-of-day summary announces new book entries.

## [0.7.0] - 2026-10-28

### Added
- **Four new mutation-only varieties:** Lavender (×3.2), Platinum (×3.5),
  Galaxy (×4.0) and Dragon (×4.0). They can turn up from any pair, like Albino
  and Glass.
- **Weighted mutations:** the overall mutation chance is still 3% per baby, but
  which mutation appears is now weighted. Albino and Glass are the most common;
  Lavender and Platinum are less common; Galaxy and Dragon are true jackpots
  (about 1 baby in 400 each).
- **Placeholder art:** until real sprites arrive, each new variety is drawn as
  a tinted copy of an existing one (Lavender and Platinum from White, Galaxy
  from Neon, Dragon from Half Black). Replace a placeholder by adding a real
  frame to `sprites.varieties` in `data/species/guppy.json`.

## [0.6.2] - 2026-10-28

### Fixed
- **Fry now keep growing in the holding tanks.** Before, a fry moved to holding
  stopped aging. Now you can move fry out of a crowded breeding tank and they
  carry on growing. Like a breeding tank, holding uses one portion of fish food
  on nights it has fry; without food they just pause.

## [0.6.1] - 2026-10-28

### Changed
- **Reverted the Market price cut from 0.6.0.** Market fish cost 130% of what
  customers pay again, so buying and reselling can't become an endless money
  loop. Profit comes from breeding: bred fish cost nothing and sell for the
  full customer price. The **Breed one** option appears again whenever a
  customer wants a fish you bought. The fry art and tank lists from 0.6.0 stay.

## [0.6.0] - 2026-10-28

### Changed
- **Market fish are now cheaper than customers pay**, so reselling a bought
  fish always makes a profit. The Market charges 70% of the customer price
  (it used to charge 130%). For example, a 3★ Black costs $7 and sells for $10,
  and a 5★ Neon costs $38 and sells for $54. Fish you breed sell for the same
  price as the same fish from the Market, and cost you nothing.
- **Fry now look like their own variety**: a small copy of the adult that
  grows to full size over 3 days, instead of one generic silver baby sprite.
  You can see at a glance what each tank's parents produced, and a real Albino
  or Glass mutation stands out.
- Each breeding tank's tab now lists its fry varieties too, e.g.
  "+ 6 fry (Red, Orange)".

### Notes
- Checked: each tank's fry come only from that tank's own pair, and mutations
  stay at 3% (3,617 simulated fry). The "same mutated fry in every tank" look
  came from the shared baby sprite, which is now gone.
- Because Market fish now resell at a profit, the **Breed one** option (offered
  only when a sale would be below cost) will rarely appear.

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
