# SavingsGoal — spec (agreed 28 Sep 2026)

A WoW Forever addon for saving toward goals (e.g. epic mounts) without accidentally spending the money.

## What it tracks

- **Income and outgoings, per character, account-wide.** Tracked via `PLAYER_MONEY` — no dependency on other addons.
- **Income by source:** Auction House sales, vendoring, quests, loot, other. So you can see which activity pays best per hour across your characters.
- **Money moves** are a third category, separate from income/outgoings: gold mailed between your own characters (e.g. funneling to the bank alt). They don't touch the surplus math.

## Goals

- Multiple goals (e.g. one mount per character), each with:
  - **Target amount** (typed in gold)
  - **Savings rate** — either a fixed amount per day, or a % of daily surplus
  - **Starting seed** — gold from current reserves allocated to the goal on day one
  - **Priority order** — combined account surplus fills goal 1 first (waterfall), then rolls into goal 2, etc.
- **Forecast:** `days to goal = (target − seed − saved so far) ÷ daily surplus`, where daily surplus is average `(income − outgoings)` per day over a trailing window (default 14 days). Also shows a combined view: "focused" (waterfall) vs "split" time to finish all goals.
- **Locked buckets:** saved gold is virtually locked. The headline number is **safe to spend** = total account gold − locked. Spending into locked gold triggers a warning. Guardrails: can't lock more than you have; optional minimum spending buffer (so your last 50g for repairs never gets locked).
- Optional hard lock (later): auto-mail the saved portion to the bank alt at each threshold, so it's genuinely out of reach.

## UI

- **Titan Panel (LibDataBroker) plugin:** headline on the bar — safe-to-spend gold, current goal progress, days-to-goal. Click opens the info screen.
- **Minimap button** (LibDBIcon, toggleable): same click behaviour.
- **Info screen:** per-goal progress bars with saved/target and days-left, account totals, per-character breakdown, income by source. Add/edit goals, set seed and rate, reorder priority, delete — via in-game dialogs and `/sg` slash commands.

## Blind-build notes

- Martin is not in the Forever beta, so this is built untested against the 1.60.1 / Interface 16001 client. Every API used (money events, mail, StaticPopup, LDB, LibDBIcon) is long-stable; risk is low.
- Test on launch day (4 Nov 2026): install, `/sg` to open, set a goal, confirm the broker feed and minimap button appear, mail gold to the bank alt and check it's logged as a money move, not income.
