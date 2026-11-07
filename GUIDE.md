# SavingsGoal — Guide

SavingsGoal is an account-wide savings addon for **WoW Forever** (Interface 16001, current version 1.0.4). It tracks income vs outgoings per character, lets you set goals — an epic mount, for example — and shows a forecast plus a **safe-to-spend** headline.

This guide covers the bits that confuse people in practice: the Titan Panel bar, what safe-to-spend actually means, and why a goal can look like it's doing nothing.

## The Titan Panel bar

If Titan Panel is installed (9.3.5 for Forever), SavingsGoal appears on the bar as a LibDataBroker feed. No code or setting in SavingsGoal controls where it sits — Titan does that.

What you see is something like:

```
0g safe | Mount 0g/100g ~37 years
```

Reading left to right:

- **0g safe** — safe-to-spend gold (see below).
- **Mount** — the top-priority goal's name.
- **0g/100g** — how much is locked into that goal so far (seed + saved) out of its target.
- **~37 years** — the forecast for that goal at your current daily surplus and rate. Very long forecasts are shown in years, not days.

Click the feed to open the info screen (`/sg` does the same). Hover it for a tooltip with every goal, safe-to-spend, and account total.

The minimap button does the same job if you don't run Titan Panel.

## Moving the SavingsGoal display on Titan Panel

Use Titan's config menu — don't drag the plugin.

1. Right-click a blank bit of the Titan bar > **Configuration > Plugins**
2. Pick **SavingsGoal**
3. Use **< Shift Left** / **> Shift Right** to swap it one place at a time with the plugin next to it.
4. Use the **Bar drop-down** to move it to a different bar (top bar 2, bottom bar, and so on).
5. The **Right-side plugin** tick moves it between the left-hand and right-hand groups on the bar.

### "There is no plugin to its left"

That means SavingsGoal is already the leftmost plugin in its group — usually the leftmost plugin on the right-hand side. Shift Left has nothing to swap with, so it can't move it any further that way.

To get it further left, change group or bar instead:

- Untick **Right-side plugin** to move it into the left-hand group, or
- Use the **Bar drop-down** to put it on a bar with empty space.

### Don't drag plugins

Titan Panel 9.3.0 and later warns against dragging plugins: after dragging, plugins can disappear on reload (portals, dungeons, etc.) and they don't snap to their final position until a `/reload`. The config-menu buttons above are the safe way to move things.

## If the bar looks busy or overlapping

The usual cause is duplication, not SavingsGoal being too wide.

- **Titan's own Gold plugin** (the gold-bag icon) shows the same gold SavingsGoal already shows. Hide it from Titan's plugin list and the overlap — faint gold text showing through behind the SavingsGoal text — goes away, and a chunk of bar is freed.
- The same applies to anything else you don't need up there: Volume, Clock, and other Titan plugins can each be hidden from the same plugin list.
- If the bar is still crowded, move SavingsGoal to another bar with the **Bar drop-down** (see above) rather than trying to squeeze it further left on a full bar.

The full SavingsGoal text is kept on purpose — the detail lives in the tooltip on hover, but the headline stays readable at a glance.

## Safe to spend, surplus, rate and keep

These four ideas are the whole addon. They are easy to mix up.

### Safe to spend

```
safe to spend = account total − seed − saved − spend buffer
```

- **Account total** is all the gold across your characters, as last seen.
- **Seed** is gold you deliberately allocated to a goal on day one.
- **Saved** is gold the addon has allocated to goals from surplus since then.
- **Spend buffer** is an optional minimum you never want locked (repairs, etc.).

If seed and saved are both 0, safe to spend equals your account total. That is correct — nothing is locked yet.

### Per-character safe to spend

The info screen's **Characters** list also shows a safe figure per toon, e.g. `Rogue-Realm: 10g (safe 10g) (+... / -...)`.

Locked gold is virtual — it isn't tied to any one character — so per-toon safe is the smaller of that toon's own gold and the account safe-to-spend: what that toon can spend right now, without mailing gold from another character. Example: account total 100g, locked 60g, account safe 40g — a toon holding 10g shows safe 10g, a toon holding 85g shows safe 40g.

Per-toon figures deliberately do **not** add up to the account safe — each is that toon's individual maximum. Mailing gold between your own characters is easy, and the addon tracks it as a money move (not income), so the account safe is still the real total limit; per-toon safe just tells you whether you need a mail run first.

### Surplus

Surplus is what's left after spending, per day:

```
daily surplus = (income − outgoings) averaged over the trailing 14 days
```

You can see it on the info screen (`/sg`): "Daily surplus (trailing 14d)". Income is split by source — Auction House, vendoring, quests, loot, other. Gold mailed between your own characters is a money move, not income or spending, so it never touches the surplus.

### Rate — a share of future surplus

Each goal has a **Rate**: either a percentage of daily surplus (`25%`, `50%`) or a fixed amount per day (`10g`).

Rate does **not** lock gold you already have. It only claims a share of surplus you earn from now on:

- Surplus 10g a day, rate 25% → 2.5g a day goes to that goal.
- A 100g goal at that rate takes about 40 days (before any seed).

Saved gold is allocated when you log in on a new day, from the surplus earned since the last login. Setting a rate today moves nothing today.

### Keep — gold held back for spending

**Keep** is separate from Rate, and it works the other way round. It takes a slice off the top of your daily surplus *before* any goal sees it, and that slice never gets locked — it stays spendable:

- Surplus 10g a day, Keep 1g a day → goals see 9g a day, 1g stays in safe-to-spend.
- Keep 25% → goals see 75% of surplus.

Keep is set from the **Keep** button on the info screen, or `/sg keep 1g` / `/sg keep 25%`. `0%` switches it off. Keep never changes safe-to-spend by itself — it only shrinks the surplus the goals (and their forecasts) have to work with.

### Seed — lock gold now

If you want gold locked into a goal immediately, use **Seed**. That allocates gold you already hold straight into the goal, so safe-to-spend drops at once. You can't seed more than the goal's target, or more unlocked gold than you hold.

In short:

| | Locks gold now? | Affects future surplus? |
|---|---|---|
| **Seed** | Yes | No |
| **Rate** | No | Yes — claims a share for that goal |
| **Keep** | No | Yes — holds a share back for spending |

## Why nothing seems to be updating

This is the most common question, and it's usually one of these:

1. **You haven't logged in on a new day since setting the rate.** Saved gold only moves on the next day's login. Same-day earnings don't appear in the goal yet.
2. **Your daily surplus is tiny.** On launch day, with almost no tracked history, a surplus of 1s 21c a day is normal. At 25%, that's about 30 copper a day to the goal — invisible on the bar, and a 100g goal forecasts in decades. The surplus grows as you earn net gold over a few days; the forecast follows it.
3. **You set Keep, not Rate.** Keep deliberately stays spendable, so safe-to-spend doesn't drop — and the goal only sees what's left after Keep.
4. **Seed is 0 and saved is 0.** Then safe-to-spend equals account total, by the formula above. Use Seed if you want an immediate lock.

To check which one it is, open `/sg` and look at:

- **Daily surplus (trailing 14d)** — if this is 0g or a few silver, there is nothing to allocate yet.
- The goal's **saved** figure, e.g. `0g / 100g` — if this is still 0 after a new-day login with a real surplus, that's a bug; report it with the surplus figure.

`/sg list` prints the same numbers to chat.

## Slash commands

```
/sg                          open the info screen
/sg add <name> <target gold> e.g. /sg add EpicMount 1000
/sg list                     goals, forecasts and safe-to-spend
/sg seed <name> <gold>       allocate current gold to a goal
/sg rate <name> <50%|10g>    set a goal's savings rate
/sg keep <50%|1g>            hold back for day-to-day spending (0% switches it off)
/sg minimap                  toggle the minimap button
/sg reset                    wipe ALL SavingsGoal data (asks first)
```

## Install

SavingsGoal is not on CurseForge yet — that is planned, but there is no date yet. Until then, install it manually from GitHub:

1. Copy the `SavingsGoal` folder into `World of Warcraft/_forever_/Interface/AddOns/` (the live Forever folder, not `_classic_beta_`).
2. Install **Titan Panel 9.3.5** for the bar feed — it also supplies the LibStub / LibDataBroker / LibDBIcon libraries SavingsGoal uses. Without it, SavingsGoal still works via `/sg` and the minimap button.
3. At character select: AddOns → tick **SavingsGoal**.

The CurseForge app can't install SavingsGoal until it's published there — it only installs addons listed on CurseForge. Once it is published, this guide will be updated with the CurseForge link, and the app will handle updates. The manual folder install above is the way until then.

To update a manual install, pull the latest from GitHub and re-copy the folder (or use the `install-sg` alias if you set one up — it removes the old in-game folder and copies the new one in one step), then `/reload` in game.

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
| `GUIDE.md` | This guide |
| `INSTALL-CHECKLIST.md` | Lean Forever addon set and launch-day test |
