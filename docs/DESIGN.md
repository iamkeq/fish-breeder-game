# Fig Tree Fish Breeder Store — Design

A cozy 2D aquarium shop game. You run a small fish store with a back room for
breeding. Nothing dies, nothing fails, and no timer punishes you.

**Engine:** Godot 4.7, GDScript. **Data:** JSON files. **Art:** placeholder
shapes and colours for now.

---

## 1. Pillars

1. **Cozy.** No fish death, no debt, no failed deliveries. The worst outcome is
   "you earned a bit less".
2. **Readable genetics.** A player should be able to look at two parents and
   guess what their babies might look like.
3. **Data-driven.** Species, traits, items, decor and request templates live in
   `data/*.json`. Adding a species should not need code changes.
4. **Testable core.** All rules (genetics, quality, pricing, scoring, inventory,
   clock) are plain GDScript classes with no scene or Node dependencies.

## 2. Core loop

```
Open shop ─► serve customers / sell / take requests ─► (≥ 4 h open) Close shop
    ▲                                                          │
    │                                                          ▼
 Restock & buy breeding stock ◄── End-of-day summary ◄── Night: breeding + fry growth
```

Earn money → restock and buy better breeding stock → breed better fish and
build nicer tanks → take better-paying requests.

## 3. Spaces

| Space | Contents (milestone 1) |
|---|---|
| **Shop floor** | 1 display tank, 1 retail shelf, 1 counter where customers appear, "Close shop" button, clock, money display |
| **Back room** | 1 breeding tank (holds a pair plus their fry) |
| **Menus** | Inventory, Buy/Restock, Tank editor, Request card, End-of-day summary |

The player switches between the shop floor and the back room with a button or
tab. There is no character walking around in milestone 1.

## 4. Day cycle

- The shop opens at **09:00**. The in-game clock runs while the shop is open.
- **Close shop** unlocks after **4 in-game hours** (13:00). The player can stay
  open longer to serve more customers.
- **Hard close at 21:00:** the shop closes itself gently, with no penalty.
- Proposed time scale: **1 in-game hour = 60 real seconds**, so the minimum
  open time is 4 real minutes. This is set in `data/economy.json`.
- The clock **pauses** while a full-screen menu is open (Buy, Tank editor,
  Inventory). That way the player is never rushed while building or shopping.
- **Overnight** (when the shop closes): breeding pairs may produce fry, fry
  grow, and food is used up. Then the end-of-day summary is shown.

## 5. Fish

### 5.1 Species (data-driven)

Each species file lists its traits, the possible values for each trait, and
which values are **rare** (they can only appear through mutation, or come from
special stock).

```json
// data/species/guppy.json
{
  "id": "guppy",
  "name": "Guppy",
  "plural_name": "Guppies",
  "base_price": 10,
  "days_to_adult": 3,
  "brood_size": [2, 4],
  "days_between_broods": 2,
  "mutation_chance": 0.04,
  "traits": {
    "body_color": { "common": ["grey", "orange", "blue", "yellow"], "rare": ["red", "albino", "metallic"] },
    "tail_shape": { "common": ["round", "fan"], "rare": ["delta", "double_sword"] },
    "pattern":    { "common": ["plain", "spotted"], "rare": ["mosaic", "tuxedo"] }
  },
  "rare_value_multiplier": 1.5
}
```

**Sex** is a built-in trait that every species has (`male` or `female`). It is
not set in the data file.

### 5.2 Inheritance (simple, not Mendelian)

For each trait in an offspring:

1. With probability `mutation_chance`, pick a random **rare** value for that
   trait (it may be one the parents don't have).
2. Otherwise, pick **mother's or father's value, 50/50**.

Sex is 50/50. Every roll uses an injected `RandomNumberGenerator`, so tests
can fix the seed and get the same results every time.

### 5.3 Quality (1–5 stars)

- **Bought fish** have the quality listed in the shop.
- **Offspring:** stars are rolled when a fry **grows up** and show as "?"
  until then. The roll starts from the parents' average quality, rounded to
  the nearest star (2.5 rounds up to 3). Then it adds a nudge: −1 (20%),
  0 (60%) or +1 (20%). The result is kept between 1 and 5 stars.
- **Food bonus:** if the fry never missed a meal, the nudge becomes
  −1 (10%), 0 (60%), +1 (30%).

Rare traits do **not** raise the star rating. They raise the price instead
(§7).

### 5.4 Fry growth

- Fry have an `age_days` count and become **adults** at `days_to_adult`.
- Fry can be viewed but not sold, and they can't go into display tanks.
- **Food:** each night, if the breeding tank has fry, it uses 1 unit of fish
  food (if any is in stock). Adults alone don't use food. Fed fry grow by 1 day. Unfed fry **don't grow that night**, but
  they never die or lose quality.
- A breeding pair (one male and one female in the breeding tank) produces a
  brood every `days_between_broods` nights. The brood size is a random number
  within `brood_size`. The tank's capacity limit (§6) caps how many fry it can
  hold.

## 6. Tanks and aquascaping (slot-based)

A tank has **1 substrate slot**, **6 placement slots** (2 back, 2 middle,
2 front) and a **fish list** up to its capacity.

| Item category | Where it goes |
|---|---|
| Substrate | Substrate slot only |
| Rocks, driftwood | Any placement slot |
| Plants | Any placement slot (tall plants are best in the back slots) |
| Other decor | Any placement slot |

Placing an item takes 1 from inventory. Removing it puts it back.

**Aesthetics score (0–100)**, a pure function of the tank's contents:

| Component | Points |
|---|---|
| Has substrate | 15 |
| Slot coverage (filled ÷ 6) | up to 25 |
| Has both hardscape (rock/driftwood) and plants | 15 |
| Variety (distinct item ids, capped) | up to 15 |
| Layering (tall items in back, short items in front) | up to 15 |
| Theme coherence (share of items with the tank's main theme tag) | up to 15 |

Each item in the data has `tags` (for example `"planted"`, `"rocky"`,
`"natural"`, `"colorful"`) and a `height` (`short`, `medium` or `tall`). The
weights live in `data/economy.json` so they can be tuned without code changes.

## 7. Economy

All numbers here are first drafts, kept in `data/economy.json`.

- **Fish price** = `species.base_price × quality_mult[stars] × (rare_value_multiplier ^ number_of_rare_traits)`
  - `quality_mult` = `{1: 0.6, 2: 0.8, 3: 1.0, 4: 1.5, 5: 2.25}`
- **Retail item price** = `item.price` (the sell price; the buy/restock cost is
  `item.cost`, which is lower).
- **Finished tank price** = `tank_base_price + Σ item.price × 1.2 + aesthetics_bonus + Σ fish prices (if sold with fish)`
  - `aesthetics_bonus = aesthetics_score × aesthetics_bonus_per_point`
- **Restocking** charges `item.cost` and the item arrives straight away
  (milestone 1).
- **Empty tanks** are an inventory item. Selling a finished tank removes that
  tank, and the player puts a new empty tank in the display spot from stock.
- **Starting state:** $150, 1 male + 1 female guppy (2★, common traits),
  1 empty display tank in place, a small amount of substrate, rocks, plants
  and food.

## 8. Customers

While the shop is open, customers arrive at the counter at random intervals
(set in the data). In milestone 1 there are two kinds:

1. **Walk-in buyer.** Wants something that is in stock: a retail item, an
   adult fish, or the finished display tank. A card shows what they want and
   the price, with **Sell** / **No thanks** buttons. "No thanks" has no penalty.
2. **Request customer.** See §9.

If no one is served, customers leave after a while with no penalty, and the
counter is free for the next one.

## 9. Customer requests

### 9.1 Milestone 1 request type: "Stocked tank"

> *"I'd love a **planted** tank with **2 orange guppies**, at least **one female**."*

A template in `data/requests/*.json` defines:

```json
{
  "id": "stocked_tank",
  "theme_tags": ["planted", "rocky", "natural", "colorful"],
  "fish_count": [1, 3],
  "constraints": ["body_color", "sex"],
  "base_reward": 60
}
```

When the request is generated, it picks a theme, a fish count, and one or two
fish constraints taken from **values the player could plausibly have** (common
values, or values present in the player's current stock). That way requests
stay achievable.

### 9.2 Flow

1. The customer arrives. The **request card** shows what they want, next to a
   **stock panel** with the relevant fish, items and empty tanks.
2. **Accept** or **Decline.** Declining has no penalty.
3. Accepted requests go to an **Orders** list (max 3). They have **no
   deadline**.
4. To fulfil an order, the player builds the tank in the display tank and
   chooses **Deliver to order**. The tank (with its fish) leaves and the payout
   is shown.

### 9.3 Scoring (pure function → 0..1 factors)

- **Match** (0–1): average of the requirement checks:
  - Theme: the share of the tank's items that carry the requested theme tag.
  - Fish count: 1 if exact, 0.5 if off by one, 0 otherwise.
  - Each fish constraint: the share of required fish that satisfy it.
- **Quality** (0–1): the average star rating of the fish, divided by 5.
- **Looks** (0–1): aesthetics score ÷ 100.

```
bonus  = base_reward × (0.4 + 0.6 × match) × (0.75 + 0.25 × quality) × (0.75 + 0.25 × looks)
bonus  = max(bonus, base_reward × 0.25)
payout = tank price (with fish, §7) + bonus
```

The customer pays the full tank value plus a bonus, so taking a request is
never worse than selling the same tank normally. A perfect delivery earns the
full `base_reward` as its bonus.
The payout card shows a breakdown, so players can see how to do better.

## 10. Inventory

One inventory with stock counts by item id, plus a list of individual fish
(each fish has a unique id). Fish are always in exactly one place: **holding**
(off-screen stock), **breeding tank**, or **display tank**.

Every action that uses stock (placing decor, selling, delivering, feeding)
goes through `Inventory.can_remove()` / `remove()`. Pure checks make sure the
player can't use what they don't have.

## 11. Architecture

```
res://
  data/                  JSON: species/, items/, requests/, economy.json
  scripts/core/          Pure logic (RefCounted classes, no Nodes)
    fish.gd  genetics.gd  quality.gd  pricing.gd  aesthetics.gd
    tank.gd  inventory.gd  request_generator.gd  request_scoring.gd
    game_clock.gd  game_state.gd  data_db.gd
  scripts/autoload/game.gd  Holds GameState, emits signals to the UI
  scenes/                shop_floor, back_room, ui/ (cards, menus, editor)
  tests/                 Built-in headless runner, fixtures, unit/ tests (see tests/README.md)
```

- **Core never references Nodes or scenes.** Scenes read state from the
  `Game` autoload and call its methods. `Game` passes the calls to the core
  and emits `changed` signals.
- **The RNG is injected** into every random function.
- **DataDB** loads and checks the JSON once at startup. Core functions receive
  data dictionaries, so tests can pass in small hand-written data.

## 12. Out of scope for milestone 1

Saving and loading, multiple display or breeding tanks, extra species, shop
upgrades, more request types, real art and audio, haggling, and customer
reputation. The design keeps room for all of these.

## 13. Decisions log

- **2026-10-26:** All the open questions were accepted as proposed. 1 in-game
  hour = 60 real seconds; open 09:00, close unlocks at 13:00, hard close at
  21:00. Walk-in customers ask for specific items. Unfed fry pause their
  growth. "Stocked tank" is the first request type. Empty tanks are stock
  items. Saving waits until after milestone 1. Everything can change later.
- **2026-10-26:** Request payout changed to *tank value + bonus*, so a request
  never pays less than selling the tank normally (§9.3).
- **2026-10-26:** Tests use a small built-in runner instead of GUT, so there's
  no third-party download (see `tests/README.md`).
- **2026-10-26 (Phase 3):** New games start with the guppy pair **already in
  the breeding tank**, and the display tank has a free **starter layout**
  (sand, Vallisneria, Java Fern, River Stone). Both are set in
  `economy.json → starting_state`. Fry stars show as "★ ?" until they grow up.
  In debug builds, holding **F** fast-forwards the clock 20×.
- **2026-10-26 (Phase 4, part 1), requested during play-testing:**
  - **Fish art:** vector guppies with a tapered body, fins with rays, patterns
    unique to each fish, and a pseudo-3D **yaw turn** (nose-on mid-turn, no
    "paper flip"). Metallic shine and albino red eyes are set in data
    (`species.render`). The debug gallery is at `scenes/debug/fish_gallery.tscn`.
  - **Fish Market (named strains):** `data/strains/*.json`, sold in priced
    tiers that are **always visible**. The buy price is the sell price ×
    `fish_market.price_multiplier` (1.3), so profit comes from breeding, not
    reselling. Bought fish go to **holding**.
  - **Supplies** can be bought in the same Market overlay.
  - **Wholesale:** any fish (fry too) can be sold instantly to the
    wholesaler for 40% of the customer price (fry: $1). Two clicks to confirm.
  - **Moving fish:** the back room lists every fish by location with move
    buttons. Fish on display have "To back room / To breeding" buttons on
    the shop floor.
  - **Customers (§8 update):** walk-ins arrive at intervals divided by a
    speed-up from **shop appeal**. Appeal = Σ (stars + 1.5 × rare traits)
    over fish on display (×1.0), in holding (×0.4) and breeding (×0.25), plus
    tank looks. The speed-up is capped at 4× and there's a 12-minute minimum
    gap. Walk-ins ask for an adult fish (better/rarer ones more often), a
    shelf item, or the display tank. 25% are request customers. Customers
    wait 90 minutes and then leave, with no penalty.
- **2026-10-26 (Phase 4, part 2):**
  - **Tank editor:** "Edit tank" under the display tank opens an overlay
    that pauses the clock. Pick a spot (button or click the tank), then place
    an item from stock; removing returns it to stock. It shows the live looks
    score, the per-component breakdown, the value, "✓ good fit" height hints
    and up to 3 tips (`Aesthetics.tips`).
  - **End-of-day summary:** money start → end, sales by category (fish,
    shelf, tanks, orders, back-orders, wholesale), Market spending, customers
    served and wandered off; new fry (with previews), **rare mutations**
    (rare traits neither parent has), fish that grew up (with stars); tomorrow:
    next brood, a low-food warning, and open orders/back-orders. Tracked in
    `GameState.day_log`, which resets each morning.
  - **Back-orders (requested in play-testing):** walk-ins sometimes wish for
    something you don't have (an item not in stock, or a Market strain + sex),
    weighted by `customers.wants.wish`. An item that sells out while a
    customer waits can be back-ordered too. "Order it in" adds it to a
    back-order list (max 5, no deadline) at **10% off**. Hand it over once you
    have it: items from stock; fish = any adult in holding/display that
    matches the strain's fixed traits, sex and minimum stars, so home-bred fish
    count. The breeding tank is never used.
  - **Shop bell:** when a customer arrives and you can't see the counter (back
    room, or a menu is open), a synthesized bell rings, and the Shop floor
    button shows 🔔 while they wait.
- **2026-10-27, guppy sprite sheet:** guppies now use `assets/fish/guppy_sheet.png`
  (cut by `tools/process_guppy_sheet.gd`). §5.1–5.2 are updated as follows:
  - **One trait, `variety`, with the sheet's 24 names.** Common (sold in the
    Market): Normal, Red, Blue, Yellow, Black, White, Grass. Bred by
    **recipes** (`species.recipes`, 30% chance per fry when a pair matches,
    either order), e.g. Red×Yellow→Orange, Red×Blue→Purple, Black×White→
    Dalmatian, Orange×White→Koi, Black×Red→Half Black, Half Black×Black→
    Tuxedo, Turquoise×Blue→Neon. **Mutation only:** Albino, Glass
    (`traits.variety.mutations`).
  - **Prices:** per-variety `value_multipliers` (×1.4 to ×3.0) replace the
    flat rare multiplier for guppies.
  - **Art:** the Normal variety uses the sheet's animated swim-right,
    swim-left and idle frames. The other varieties use their still frame plus
    a tail-wave shader (`scenes/fish_wave.gdshader`). Fry use the sheet's 3
    baby frames. Turning narrows the fish to 45% width, never flat. The
    sheet's death/hurt rows and eggs are deliberately unused (cozy; guppies
    are livebearers). Species without `sprites` still use the vector fish.
  - **Names:** fish are named "<Variety> Guppy". The summary celebrates
    "🎨 New variety!" (recipe) apart from "✨ Rare mutation!".
- **2026-10-27, decor sprite sheet:** every plant, rock, driftwood and decor
  item now comes from `assets/decor/decor_sheet.png` (cut and repacked from
  your sheet by `tools/cut_sheet.gd`). There are 45 items: 9 tall, 10 medium
  and 10 short plants, 10 rocks and pebble piles, 3 driftwood, and 3 decor
  (Coconut Hut, Clay Pot, Ruined Arch). Red plants are tagged "colorful".
  Items carry `sheet` + `sprite` [x, y, w, h]. The tank draws them sized by
  height class, and lists show them as icons. Substrate, food and tanks keep
  their colour swatches (they're not on the sheet).
- **2026-10-28 (v0.3.0):**
  - **Up to 4 breeding tanks** (`economy.breeding_tanks`: max 4, extra costs
    $75/$100/$150). Locations are "breeding", "breeding2" ... "breeding4".
    Each tank pairs, breeds, feeds and counts brood nights on its own, so
    there's no cross-breeding between tanks.
  - **Market tabs:** Fish / Decorations / Supplies.
  - **Clock:** 48 real seconds per in-game hour (25% faster).
- **2026-10-28 (v0.4.0), breed-to-order:** fish remember what you paid
  (`Fish.paid`, set by `buy_strain`). When a walk-in wants one of your fish and
  their price is below what you paid, the counter offers **Breed one**. That
  adds a back-order with the fish's `traits` + `sex`, the quoted price, a
  `due_day` 2–3 days ahead (`backorders.breed_wait_days`) and `keep_id`. It can
  be handed over from the due day with any matching adult in holding, display
  or a breeding tank, except the kept fish and each tank's breeding pair.
- **2026-10-28 (v0.6.0):**
  - **Pricing:** `fish_market.price_multiplier` changed from 1.3 to 0.7. The
    Market sells at 70% of the customer price, so bought fish resell at a
    profit and bred fish are worth the same as Market ones (but are free).
    This replaces the earlier rule that "profit comes from breeding, not
    reselling". The breed-to-order offer still triggers only below cost.
  - **Fry art:** fry use their own variety's sprite at 40%→100% size by age;
    the sheet's generic baby frames are no longer used.
- **2026-11-11 (v0.22.0), money-loop rebalance:**
  - A headless bot (`tools/playbot.gd`, styles casual / optimizer / lazy;
    optional `--tanks=sell`) and `tools/exploit_probes.gd` check the economy.
    Run: `"$GODOT" --headless --path . -s res://tools/playbot.gd -- --days=100
    --seed=1 --style=casual`. Re-run both after any pricing change.
  - Tank sale = Market build cost (tank + substrate + placed items at `cost`)
    x (1 + `tank_pricing.premium` 0.06 + up to `looks_bonus_max` 0.06) + fish.
    Item retail `price` is about 1.25x `cost` (Fish Food is 1.5 because prices
    are whole dollars). Special-order `stocked_tank` base_reward 45.
  - Known and accepted: tank customers also buy fish at full price, so a shop
    with surplus fish gets an extra outlet (selling+rebuilding a tank is at
    most about 1.3x normal income). The optimizer bot still ends 100 days
    near $107k (casual about $12.6k); that comes from fish, collector and
    show income, which was left alone. Late-game money sinks are the open
    item if this needs flattening.
- **2026-11-11 (v0.21.0), standing orders:**
  - `standing_orders` (item -> enabled, reorder_at, quantity),
    `order_money_floor` and pending `deliveries` are saved. Orders are paid
    through `_spend` at `item_cost()` (the same price as `buy_item`) and
    arrive `delivery_days` (1) later, at `open_day`.
  - `process_standing_orders()` runs after sales, placements, at end of
    night and at open of day. It orders while `stock + pending <=
    reorder_at`, and never below the money floor. Setting a rule does not
    order by itself, so spin-boxes can't trigger orders while scrolling.
  - It is separate from the Stock clerk and Feeder; they don't double-charge.
    Prices are unchanged; retail decorations still sell at a margin by design.
- **2026-11-11 (v0.20.0), shop staff:**
  - `data/staff.json`; hires are `{id, name, task, hired_day, color}` so stats
    and skills can be added later. One hire per task.
  - The game has no manual feeding (fry eat fish food automatically), so the
    Feeder is a safety net that buys food when fry would go unfed, and the
    Stock clerk keeps food topped up. They overlap; consider merging or
    adding new supplies. Both pay the normal Market price.
  - Spare inventory decorations double as retail shelf stock, so the
    Decorator leaves `decorator_keep` (1) of each item.
  - Wages are paid after the night's work, are not routed through `_earn`,
    and are skipped (never debt) if unaffordable. Staff use no rng.
- **2026-11-11 (v0.19.0), gallery:**
  - Gallery entries are plain dictionaries: `gallery_favorites()` (live
    favourites, keys `fav:<id>`) and `gallery_hall()` (one per `show_history`
    record, keys `hof:<index>`, which stays valid because the history is
    append-only). Purely cosmetic: no money or star effects.
  - `gallery_pins` (saved) hold entry keys; pins whose favourite was
    un-marked are dropped lazily and don't count. Slots come from
    `economy.gallery.pin_slots` and need `has_unlock("gallery_wall")`.
  - The shop floor has no free wall, so pinned frames sit at the foot of the
    Retail shelf panel. A strip above the tank would cost about 80px of tank.
- **2026-11-11 (v0.18.0), fish shows and ribbons:**
  - `data/shows.json` rotates through classes; the show number comes from the
    calendar (`ceil(day / every_days)`), so cadence survives old saves.
    `Shows` (scripts/core/shows.gd) holds the scoring helpers.
  - Score = stars * 18 + value_step * 6 + hidden purity * 0.25 + judge swing;
    value_step = max(1, round(trait multiplier)). Rivals are anonymous scores
    around `rival_strength`; base was raised from 45 to 70 after simulation.
    A 5★ pure Dragon wins almost always by design; raise `max` /
    `grand_bonus` if that becomes too easy.
  - Prizes go straight into money like book rewards (not a sale, not in
    `total_earned`). Reputation amounts live only in `reputation.json`.
  - `show_history` snapshots (fish traits, stars, name, purity) outlive the
    fish, for the gallery. Hints use visible stars and variety only, never
    hidden purity.
- **2026-11-11 (v0.17.0), line purity and the Lab:**
  - `Fish.purity` / `Fish.scanned` are saved. `Purity` (scripts/core/purity.gd)
    holds the static rules. "Same variety" means identical `traits` (sex
    ignored). Numbers live in `economy.purity` and `economy.lab`.
  - Purity applies through `_star_nudges` as a flat probability shift on top
    of the food odds. It is hidden until scanned.
  - The certified price bonus lives in `Pricing.fish_price` and applies only
    when `scanned and paid == 0 and strain_id == ""`, so Market fish never get
    it. Typical extra revenue per scan is below the $20 fee; the Lab is for
    information and records, not profit.
  - Lab gated by `has_unlock("lab")` (reputation level 3).
- **2026-11-11 (v0.16.0), shop reputation:**
  - `data/reputation.json`: point values per source, seven levels with
    `effects` (`extra_customers`, `extra_orders`) and `unlocks` ids
    (`lab`, `fish_show`, `staff`, `gallery_wall`). Later features gate on
    `GameState.has_unlock(id)`. Reputation never decreases and is never
    earned by spending.
  - Customers arrive on a timer, so `extra_customers` is an arrival-rate
    boost via `customer_speed()` (`customer_speed_per_extra` 0.08 per point),
    stacking with the shop-sign upgrades; the minimum-interval floor stays.
  - `check_goals` now loops, because goal rewards earn reputation that may
    complete a reputation goal.
- **2026-11-11 (v0.15.0), fish names and favourites:**
  - `Fish.nickname` and `Fish.favorite` are saved. `GameState.fish_title()`
    is the name used in text. `economy.favorites.max` caps favourites.
  - Favourites are excluded in `fish_for_sale` (so customers, collectors and
    wishes), `sell_fish`, wholesale, back-order hand-over, tank pricing and
    order scoring; display-tank sale/delivery leaves them in holding. They
    cannot be moved into order tanks. Later features (gallery, shows) build
    on the favourite flag.
- **2026-11-12 (v0.28.0), food per tank, Spawning Pellets:**
  - Saved `tank_food` maps a location to a food item; missing means
    `economy.default_food`. `_eat_food()` tries the choice, then the default,
    then any food. Pellet tanks with a breeding group eat every night even
    without fry.
  - Food items may have `brood_multiplier`; `Genetics.breed()` takes an
    explicit size and `scale_brood()` rounds the fraction at random, so extra
    fry are real offspring of that pair. Capacity still limits the brood.
- **2026-11-12 (v0.27.0), regular customers:**
  - `data/regulars.json` holds the rules and 8 characters (favourite
    trait/value, min stars). `scripts/core/regulars.gd` is the pure maths
    (loyalty level, tip). `regulars_state` (saved) tracks met, visits, loyalty
    and purchases.
  - `_new_customer()` may swap a walk-in for a regular: matching fish, then a
    favourite-themed special order at loyalty 3+, then a wish_fish, else an
    ordinary walk-in under their name. Met regulars are twice as likely, and
    nobody visits twice a day.
  - Tips round down and apply only to the shop's own fish prices (fish and
    collector sales, bred-fish back-orders) and to a special order's bonus,
    never to Market-priced goods or tank value, so the max +20% tip can't make
    buy-and-resell pay (tested for every Market strain).
- **2026-11-12 (v0.26.0), auto shelf sales, Growth Flakes, holding fed first:**
  - `tick_customers()` serves an `item` customer on arrival when it's in stock
    (`economy.customers.auto_sell_shelf_items`), through `serve_customer()` so
    money, reputation and stats match a manual sale. Sales queue in the
    transient `auto_sales`; `Game` drains it and emits `auto_sale` (ding and
    toast), never `customer_arrived` (no bell).
  - Food items may have `growth_days`; `_use_food()` uses the fastest food in
    stock and returns its growth. Growth is capped at `days_to_adult`, so the
    grow-up star roll still happens exactly once. The Auto-Feeder is free
    growth of 1 unless faster food is in stock.
  - `end_day()` feeds holding before the breeding tanks; `unfed_places` in the
    summary names hungry groups.
  - `tools/playbot.gd` books auto shelf sales and the standing orders they set
    off, so its money reconciliation still balances.
- **2026-11-11 (v0.14.0), harem breeding, stats, starting choices:**
  - `GameState.breeding_group()` is the sire (first adult male with an adult
    female of his species in the tank) and up to
    `breeding_tanks.max_mothers` mothers; each mother broods on the tank's
    shared brood night. `breeding_pair()` remains as [first mother, sire].
  - `records` (saved) holds worded personal bests `{amount, what, day, tie}`;
    whole numbers only, so they survive the JSON round trip.
  - `data/new_game.json` lists starts and challenges. Challenge rules are
    read through `challenge_rule()`: `starting_money`,
    `market_fish_until_day`, `mutation_chance_multiplier` (capped at 0.5),
    `customers_buy_only_mutations`. `Game.needs_setup` shows the new-game
    screen only in real runs with no save; scripted and headless runs start
    the standard game.
- **2026-11-11 (v0.13.0), recipe generations, book rewards, collectors:**
  - `Genetics.pair_generation()` is 1 + the deeper parent's
    `recipe_generation()` (0 for non-recipe values). Five generation-3 guppy
    recipes added (placeholder art).
  - `economy.breeding_book` sets one-off rewards per discovery and per
    completed generation; `GameState._discover()` pays them straight into
    money (not a sale). `book_bonuses` is saved; old saves get no back pay.
  - Collector customers (`customers.collector`, `wants.collector`) pay a star
    multiplier for adults with `paid == 0` and no `strain_id`, i.e. bred by
    the player. Market fish are excluded so there is no resale loop.
  - First change made with the plan / delegate / review workflow: the lead
    wrote the plan, the `fish-dev` Sonnet agent implemented it, the lead
    reviewed. The agent corrected the plan's Tiger recipe (Leopard ×
    Snakeskin would have been generation 2).
- **2026-11-11 (v0.12.0), saving, goals, upgrades:**
  - *Saving:* `GameState.to_dict()` / `from_dict()` hold everything that
    lasts between days (not the customer at the counter or today's log).
    `SaveFile` writes JSON to `user://save.json` and turns whole-number floats
    back into ints on load. The Game autoload saves after each night and loads
    on start; headless and `-s` script runs never touch the save.
  - *Goals:* `data/goals.json` entries are `{metric, target, reward}`.
    `GameState.goal_value()` reads the metric (lifetime `stats` counters, or
    live values like recipes found). `check_goals()` pays each reward once;
    rewards are not sales, so they don't count towards "best day".
  - *Upgrades:* `data/upgrades.json` entries carry `effects`; rules ask
    `upgrade_effect(name)` for the total. One-off purchases only, so they
    can't create a money loop.
- **2026-11-04 (v0.11.0), animated decor:** items may carry `frames` (rects
  on their sheet), `fps` and `body_height` (pixels of the object at the bottom
  of each frame). TankView sizes the body by the height class and lets the
  rest (bubbles) extend above; `sprite` stays a still crop for icons. Breeding
  tanks without a substrate draw `breeding_tanks.substrate` (fine sand) and
  the `breeding_tanks.air_stone` animation (same fields as an animated item,
  plus `x`, its spot across the water) behind their decor.
- **2026-11-04 (v0.10.0), fish wishes:** `GameState.wishable_fish()` lists
  single-trait Market strains (`source: market`) and breeding-book-discovered
  recipe children (`source: bred`), excluding mutations and anything already
  for sale. `fish_wish_terms()` prices them: market = strain cost less
  `backorders.discount` (10%: a penalty for being out of stock), wait `market_wait_days`; bred = price of a
  `bred_reference_stars` fish × `bred_price_multiplier`, wait `bred_wait_days`.
  Back-orders now always match on traits + sex. The old strain-wish path and
  `Customers.matches_strain` are removed.
- **2026-10-28 (v0.9.0), order tanks:** accepted orders get a stable `id`, a
  `customer` name and an optional `tank` (an order tank at location
  `Fish.order_location(id)`, set up from a spare tank item).
  `deliver_order(i, from_order_tank)` delivers either that tank or the display
  tank (an unused order tank then goes back to stock). Cancelling dismantles the
  order tank back into stock. Order-tank fish aren't for sale and don't count
  toward shop appeal. The UI is `scenes/orders_room.gd`, and the tank editor
  now takes a location and has a Fish section.
- **2026-10-28 (v0.8.0), breeding book:** `GameState.discovered_recipes` /
  `discovered_mutations` hold the first day each recipe (keyed by trait + sorted
  parents) or mutation was bred. Entries are added in `_night_breed` and listed
  by `book_recipes()` / `book_mutations()`. The UI is `scenes/ui/breeding_book.gd`.
  Only breeding unlocks entries.
- **2026-10-28 (v0.7.0):** four new mutation-only varieties (Lavender,
  Platinum, Galaxy, Dragon). `traits.variety.mutation_weights` weights the pick
  (3/3/2/2/1/1); the overall chance is still `mutation_chance` (3%).
  `sprites.placeholders` draws a variety without art as a tinted copy of
  another (`base` + `tint`) until its sprite exists.
- **2026-10-28 (v0.6.2):** fry grow in holding as well as in breeding tanks.
  Holding is fed as one more group (1 food portion per night when it has fry).
- **2026-10-28 (v0.6.1):** pricing reverted to `price_multiplier` 1.3.
  **Design rule (from the player):** the incentive is to breed. Market fish
  must cost more than customers pay, so there's no infinite money loop from
  buying and reselling.
- **2026-10-28 (v0.5.0), Closed for restock (playtesting):** `GameState.restocking`
  stops new customers (anyone waiting leaves, no penalty) and `time_scale()`
  returns `clock.restock_speed` (4), which the Game autoload multiplies into
  the clock. It persists across days until turned off. `restock_speed: 0`
  hides the button. It may be removed later.
