# SavingsGoal

An account-wide savings-goal addon for **WoW Forever** (Interface 16001). Track income vs outgoings per character, set goals like epic mounts, and get a "days until goal" forecast plus a **safe-to-spend** headline number.

Built blind (no beta access) — every API used is long-stable, but treat launch day as the first real test.

## Install

1. Copy the `SavingsGoal` folder into `World of Warcraft/_forever_/Interface/AddOns/`
   (live folder since launch 4 Nov 2026 — `_classic_beta_` was the beta folder only).
2. Optional but recommended: install **LibStub**, **LibDataBroker-1.1**, and **LibDBIcon-1.0**
   (they ship with Titan Panel, so installing Titan Panel covers all three).
3. At the character select screen: AddOns → tick **SavingsGoal** (and "Load out of date AddOns" if it asks).

## Use

- `/sg` — open the info screen (or click the Titan Panel feed / minimap button).
- Add a goal: click **Add goal**, or `/sg add EpicMount 1000`.
- **Seed** a goal with gold you already have; set its **Rate** (`50%` of surplus, or `10g` per day).
- Goals fill in priority order (waterfall) — use `^`/`v` to reorder.
- The Titan bar shows your safe-to-spend gold and the top goal's progress.

## How it works

- Every money change is logged per character and attributed to a source: Auction House (mail from the auction house), vendoring (while a merchant window is open), quests, loot, or other.
- **Money moves** — gold mailed between your own characters — are tracked separately and never count as income or spending. (Assumption: gold you mail is going to your own bank alt.)
- Each login, the trailing-14-day daily surplus is computed and allocated to goals in priority order. Forecast: `(target − seed − saved) ÷ daily surplus`.
- Spending into locked goal gold prints a warning. You can't lock more than you hold.

## Files

| File | What |
|---|---|
| `SavingsGoal.toc` | Addon manifest (Interface 16001) |
| `core.lua` | Events, saved-variable DB, money tracking & source attribution |
| `goals.lua` | Goal CRUD, surplus math, forecasts, waterfall allocation |
| `broker.lua` | Titan Panel / LibDataBroker feed + minimap button |
| `ui.lua` | Info screen + dialogs |
| `slash.lua` | `/sg` commands |
| `SPEC.md` | The agreed spec this was built from |

## Launch-day checklist

- [ ] Addon loads, `/sg` opens the info screen
- [ ] Titan feed and/or minimap button appear and show figures
- [ ] Buy/sell something: income attributed to the right source
- [ ] Mail gold to the bank alt: logged as a money move, not income
- [ ] Set a goal, seed it, check the forecast math
