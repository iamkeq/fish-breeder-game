# Fig Tree Fish Breeder Store — Implementation Plan (Milestone 1)

Goal: the smallest playable version of the loop described in
[DESIGN.md](DESIGN.md). Each phase ends in something that runs or passes tests,
and the core logic is tested before any UI is built on top of it.

## Phase 0 — Project setup

- [x] Run `git init` and keep the existing `.gitignore` (`.godot/` is
      already ignored).
- [x] Create the folder layout from DESIGN §11.
- [x] Test runner: a small built-in headless runner (`tests/run_tests.gd`) instead of GUT,
      so there is no download. Command:
      `godot --headless --path . -s res://tests/run_tests.gd`
- [x] Add `tests/README.md` explaining how to run the tests.

**Done when:** an empty sample test passes from the command line.

## Phase 1 — Data and data loading

- [x] `data/species/guppy.json`
- [x] `data/items/*.json`: substrate (2), rocks (2), driftwood (1), plants (3,
      mixed heights), decor (2), fish food (1), empty tank (1). Each has `id`,
      `name`, `category`, `cost`, `price`, `tags`, `height`, and a
      placeholder `color`.
- [x] `data/requests/stocked_tank.json`
- [x] `data/economy.json`: quality multipliers, aesthetics weights, tank pricing,
      clock settings, customer spawn rates, and the starting state.
- [x] `scripts/core/data_db.gd`: loads, checks required fields, and reports clear
      errors.
- [x] Tests: loading succeeds on the real data; a missing field or bad
      reference gives a readable error.

## Phase 2 — Pure core logic (test-first)

Each class lives in `scripts/core/` and has a matching `tests/unit/test_*.gd`.

| Class | What it does | Key tests |
|---|---|---|
| `fish.gd` | Fish record (id, species, sex, traits, stars, age, location) and `to_dict`/`from_dict` | Round trip; `is_adult` |
| `genetics.gd` | `breed(mother, father, species, rng, fed)` → offspring list | With a fixed seed: each trait comes from a parent unless it mutates; a mutation always gives a rare value; sex is roughly 50/50 over many rolls; the brood size stays in range |
| `quality.gd` | Offspring star roll | Result stays in 1–5; the parents' average is centred; the fed bonus shifts the distribution (checked statistically with a seed) |
| `inventory.gd` | Stock counts and the fish list | `can_remove` is false when stock is short; `remove` never goes negative; adding and removing fish; moving fish between locations |
| `tank.gd` | Substrate slot, 6 placement slots, fish | Slot rules by category; capacity; place and remove return items to inventory |
| `aesthetics.gd` | 0–100 score | Empty tank = 0; each part of the score adds up correctly; the score is capped at 100 |
| `pricing.gd` | Fish, retail and tank prices | Hand-checked examples; rare-trait multiplier; tank priced with and without fish |
| `request_generator.gd` | Builds a request from a template and the current stock | Always within the template's limits; constraints use values the player can actually get |
| `request_scoring.gd` | Match, quality and looks → payout plus breakdown | Perfect = maximum payout; empty or wrong tank = minimum payout, never below it; the fish-count off-by-one rule |
| `game_clock.gd` | Time, `can_close`, auto-close, pause | Close is locked before 4 h and unlocked at or after 4 h; auto-close at 21:00; pausing stops time |
| `game_state.gd` | Ties everything together: money, day, tanks, orders; `end_day()` runs breeding, growth and food | Fry grow only when fed; broods follow `days_between_broods`; selling adds money and removes stock; you can't sell fry |

**Done when:** all of these tests pass headless. ✅ 105 tests passing (2026-10-26).

## Phase 3 — Game autoload and bare scenes

- [x] `scripts/autoload/game.gd`: owns `GameState` and the RNG, exposes
      actions (`sell_fish`, `place_item`, `end_day`, …), and emits signals.
- [x] `scenes/main.tscn`: top bar (day, clock, money), a Shop/Back room
      switch, and a "Close shop" button (greyed out until allowed).
- [x] `scenes/shop_floor.tscn`: display tank view, shelf, counter.
- [x] `scenes/back_room.tscn`: breeding tank view.
- [x] Placeholder fish: a coloured ellipse plus a tail polygon based on traits,
      with a pattern overlay, swimming around inside the tank.

**Done when:** you can launch the game, watch the clock run, switch rooms and
close the shop. ✅ Done 2026-10-26. Also added: the end-of-day summary overlay (basic
version), a starter display tank, the starting pair in the breeding tank, and a
back-room fish list. Debug: hold F to fast-forward the clock.

## Phase 4 — Feature UI (one at a time, playable after each)

Progress: ✅ All of Phase 4 done (2026-10-26). Also added: back-orders, the shop bell, wholesale selling,
and named-strain tiers. Item 1 (inventory) is covered by the retail shelf, the back-room fish list and the
editor's stock list.

1. **Inventory panel:** stock counts and fish list with stars and traits.
2. **Buy/Restock screen:** buy items and breeding fish, limited by money.
3. **Tank editor:** pick an item from stock and place it in a slot; live
   aesthetics score and price preview.
4. **Breeding:** move a male and a female into the breeding tank; fry appear
   overnight; move adults out to holding or to the display tank.
5. **End-of-day summary:** money earned, new fry, fry grown, food used.
6. **Walk-in customers:** spawn at the counter and show a Sell / No thanks card
   (fish, retail item, finished tank).
7. **Request customer:** request card with a stock panel, Accept/Decline,
   Orders list, "Deliver to order", and a payout breakdown card.

**Done when:** a full day can be played: restock → build tank → serve and
sell → take and deliver a request → close → see the fry grow the next day.

## Phase 5 — Polish pass for the slice

- [ ] Gentle feedback: coin pop-ups, a chime sound (placeholder), and
      tooltips explaining stars and rare traits.
- [ ] Balance check: play 5 in-game days and adjust `economy.json`.
- [ ] Update DESIGN.md with anything that changed.

## Order of work and checkpoints

I'll stop for your review at:
1. After **Phase 2** (all core logic and tests, before any UI).
2. After **Phase 4** (the playable slice).

## Risks and notes

- **GUT on Godot 4.7:** if the latest GUT release doesn't support 4.7 yet, I'll
  use GdUnit4 instead, or a small built-in test runner script. Nothing in the
  core depends on the test framework.
- **Balance numbers** are guesses. Keeping them all in `economy.json` makes them
  cheap to change.
- **Using a real-time clock in tests:** `game_clock.gd` takes elapsed time
  as a parameter, so tests never wait on real time.
