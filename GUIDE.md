# SavingsGoal — Guide

SavingsGoal is an account-wide savings addon for **WoW Forever** (Interface 16001, current version 1.0.16). It tracks income vs outgoings per character, lets you set goals — an epic mount, for example — and shows a forecast plus a **safe-to-spend** headline.

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

## Look: Modern or Classic (v1.0.6)

The info screen has two looks, and you can switch any time — the choice is saved per account.

- **Modern** (default): flat dark bars, gold section headers with thin dividers, safe-to-spend big and gold on the left with the account total muted on the right, muted secondary text.
- **Classic**: the pre-1.0.6 layout — single-sentence headline ("Safe to spend: … Account total: …"), plain section titles, glossy Blizzard bars.

Switch with the **Look** button at the top of the info screen (it shows the current look), or `/sg look classic` / `/sg look modern`. The outer window stays Blizzard's in both looks, so the title bar, close button, drag and Esc all keep working.

v1.0.7 fixed two glitches in the Modern look spotted from a screenshot: the goal bar's label sat tucked under the bar, so its top — the "~" in "~5 years" first — was clipped behind the bar's bottom edge; it now sits 6px clear below the bar. And goal names / character rows that had no explicit colour came out gold (the default label colour in-game is gold, not white), so Modern now colours goal names white and character rows muted like the other secondary text.

## Transfers between your own characters (v1.0.8)

Gold mailed to your bank alt is a **money move**, not income: it never touches surplus, forecasts or safe-to-spend, and the info screen now shows a "Transfers between own characters" total so you can see it was recognised.

Two things that used to misfile it as "Other" income are fixed: the inbox sender can arrive as the full "Nox-CAMWOW EU4 Realm 1 PvE" (not just "Nox"), which the old check failed on, and if the inbox scan misses a mail for any reason, the sending character now leaves a note in a shared ledger, so the receiving alt recognises the same amount as a transfer when it arrives.

If an amount was already misfiled before this version, fix it on the receiving character with `/sg move <amount>` — e.g. `/sg move 50s` moves 50 silver out of "Other" income into transfers, including today's daily income so the surplus is corrected too.

## How income and spending are categorised (v1.0.9)

**Loot:** when you loot gold, the game prints "You loot …" and the addon marks that amount as loot. It used to need one loot message to match one money change exactly, so loot leaked into "Other" whenever several loots were batched into a single money change, or a second loot overwrote the first before the money arrived. Now looted amounts accumulate, a money change is split (the looted part is loot, the rest is judged on its own), and if the loot message arrives *after* the money was already filed as "Other", it is moved into Loot.

**Mail fees:** postage (30c per mail) is now its own spending category, "Mail fees". If you mail gold, the sent gold is still a money move and the 30c postage is split off as a mail fee; a mail with no gold attached is charged the same way while the mailbox is open. Spending is shown in its own "Spending by source" section on the info screen (Vendoring / repairs, Mail fees, Auction House, Other) — previously spending was tracked but never displayed, so mail fees were invisible as well as miscategorised.

**The rest:** Auction House mail is Auction House, vendoring while a merchant window is open is Vendoring, a quest turn-in is Quests, and anything with no other explanation is Other. Gold mailed between your own characters is a money move, never income or spending (see above).

**Repairs (v1.0.11):** repair bills are their own spending category, "Repairs", in the Spending by source section — they used to be lumped in with vendor purchases. This follows the established pattern from GoldLedger and Gold Digger: hook `RepairAllItems()` and capture `GetRepairAllCost()` *before* the money changes, because checking the cost after the repair always returns 0 (the gear is already fixed). If guild funds cover part of the bill, the part you paid is still filed as Repairs; a purchase bigger than the repair bill is not mistaken for one. One limit: repairing a single item with the repair cursor (rather than Repair All) still lands in Vendor purchases, and vendor spending recorded before v1.0.11 includes old repair bills — those can't be separated after the fact.

**Auction listing fees (v1.0.14):** the deposit you pay when listing an auction is now filed as "Auction House" spending — it shows in the Spending by source section. It used to fall through to "Other", because although the "Auction House" spending category existed, the addon never actually watched the AH window being open; only AH *income* (sales arriving by mail) was ever filed as AH. A spend while the AH window is open is now AH spending. `/sg reclassify` works for spending too, so a fee already filed as Other can be moved: `/sg reclassify <amount> other ah` (e.g. `/sg reclassify 1s other ah`). Spending categories are ah, vendor, repair, mail or other.

**AH sale proceeds (v1.0.16):** a sale of 8s 60c arrived and was filed as "Other" — the inbox scan only recognised AH mail by its sender, and that proved unreliable. Sales are now recognised by the mail subject too ("Auction successful: …", the check Accountant uses), the mailbox is scanned the moment it opens so a sale mail is registered before it can be taken, and money arriving batched with another gain is split — each pending mail is taken out of the lump and the rest judged on its own, so taking several mails at once no longer loses the match. New diagnostic: `/sg mail` lists the money mail the addon has spotted in your inbox (amount, kind, sender, subject) — if a sale ever misfiles again, run that at the mailbox and it shows exactly what the addon saw. The 8s 60c itself can be fixed with `/sg reclassify 8s 60c other ah`.

**Training, travel, trading, bank (v1.0.15):** four more contexts that used to leak into "Other", found by anticipating the same pattern and checked against how the top gold trackers do it (Accountant, GoldLedger, Gold Digger, pH — see below). Learning a spell at a class trainer is "Training" spending; a flight fare is "Travel" spending; gold given or received in the trade window is "Trading" (both directions); deposits and withdrawals at any bank — personal, guild or warband — are money moves, like mailing gold to an alt, never spending or income. Each counts while its window is open and for a few seconds after it closes, because the money change can arrive after the close. **Outbid refunds (v1.0.15):** when you're outbid, the AH returns your bid by mail — that now reverses the earlier AH expense instead of counting as income (Accountant does the same); if no matching spend was recorded, the refund is a money move. **Quest rewards (v1.0.15):** the exact money reward from `QUEST_TURNED_IN` is now filed as Quests, split out of a batched money change; a turn-in with no money reward no longer claims the next unrelated gain. **Stale loot (v1.0.15):** pending loot expires after 10 seconds with no money change behind it, so it can't claim a later unrelated gain of the same size. One caveat from the research: which bank events fire is disputed — Gold Digger says The War Within folded guild/warband bank into `BANKFRAME_OPENED`/`CLOSED`, while Warband Accountant and retail Accountant still register `GUILDBANKFRAME_OPENED`/`CLOSED` — so both families are registered, and whichever the Forever client fires is caught.

**How other addons do it:** SavingsGoal's detection now matches GoldLedger's published table — Vendor = merchant window open, Repair = `RepairAllItems()` hook, Auction House = AH window + AH mail sender, Mail = mailbox open, Quest = quest turn-in, Loot = loot window (plus the "You loot …" chat message), Trade = trade window. Accountant, the long-running original, uses the same event/context approach with categories for training, taxi fares, trading, mail, looting, quests, repairs, merchant and auction house. Researched for v1.0.15 (Accountant, GoldLedger, Gold Digger, pH, Warband Accountant): two architectures exist — sticky window-mode (Accountant) vs hooks that capture the exact cost before the money moves (pH: `RepairAllItems`, `TakeTaxiNode` + `TaxiNodeCost`); SavingsGoal uses window-mode with grace periods, which matches Accountant's own "window closes before money" notes for taxi, loot and quests. Known gaps left as follow-ups: single-item cursor repairs (Accountant catches them by baselining money + repair cost at `MERCHANT_SHOW` and watching durability changes — the hook approach misses them); COD mail (no researched addon handles it); barber, transmog and talent respec (cheap window-event additions — Mob Ledger confirms they exist as sources on Forever); guild-funded repairs are skipped by pH (player didn't pay) while SavingsGoal files the part the player paid.

**Fixing a misfiled amount (v1.0.10):** the loot fix only applies to new loot — anything filed as "Other" before the fix stays in "Other" until you move it. On the character that earned it: `/sg reclassify <amount> other loot` (e.g. `/sg reclassify 50s other loot`). Categories are ah, vendor, quest, loot or other; totals don't change, only the bucket. If loot still lands in "Other" after updating, loot something and run `/sg last` straight away — it reports what the gain was filed as and how much pending loot the addon had seen at the time, which shows whether the loot message ever reached it. (v1.0.12: `/sg last` now reports the *final* filing — before that it kept saying 'other' even after the loot message had moved the gain into Loot — and also prints the current Loot and Other totals, so you can see the bucket directly. The late-chat window is 10 seconds.)

**Activity log (v1.0.13):** every money change is recorded — time, amount, source, and what the addon could see at the time (pending loot, whether the loot window had just been open, merchant, quest). `/sg log` prints the last 10 entries. It is the source of truth when a filing looks wrong: instead of guessing from a screenshot, the log shows exactly what the addon observed. The log is kept in SavedVariables (last 100 entries, account-wide).

**How loot is detected (v1.0.13):** chat text turned out to be unreliable on Forever — on the Midnight client the game hands chat text to addons as a protected "secret" that errors when touched (Loot Pro hit the same thing), and some gold is only reported as a system message rather than `CHAT_MSG_MONEY` (XLoot has the same workaround). So loot now uses four independent signals, in order: (1) the loot window is scanned for coin slots when it opens — the money is sitting there before it is ever taken, so this needs no chat at all, and it works for corpse loot and pickpocketing alike; (2) a 2-second grace period after the loot window opens, so auto-loot closing the window before the money arrives doesn't lose the signal; (3) the loot chat message, read through a `ChatFrame_AddMessageEventFilter` (which can read the text) and also listened for on `CHAT_MSG_MONEY`, `CHAT_MSG_SYSTEM` and `CHAT_MSG_LOOT`; (4) if the message arrives after its money, the gain is moved from Other into Loot (10-second window). The signals are de-duplicated, so one loot can't be counted twice.

## What the info screen shows (v1.0.5 polish)

- **Goal bars** show a % complete, e.g. `25g / 100g (25%)`, and change colour as you get closer: green while working, gold at 75%+, bright green when complete.
- **Today** line under the daily surplus: today's income, spending and net in full gold/silver/copper, e.g. `Today: +2g 0s 0c / -0g 50s 0c (net 1g 50s 0c)`.
- **Goal complete** prints a one-time chat line — `Goal complete: Mount — 100g saved!` — when a goal fills up, whether by seeding it or by surplus. It only ever prints once per goal.
- **Per-character safe to spend** in the Characters list (see above).

Ideas from other gold addons that are *not* in SavingsGoal yet, deliberately: a 30-day projected-pace graph, gold/hour while farming, and multiple movable tracker windows. Those are possible follow-ups if they prove useful in play — the addon stays lean for now.

## Slash commands

```
/sg                          open the info screen
/sg add <name> <target gold> e.g. /sg add EpicMount 1000
/sg list                     goals, forecasts and safe-to-spend
/sg seed <name> <gold>       allocate current gold to a goal
/sg rate <name> <50%|10g>    set a goal's savings rate
/sg keep <50%|1g>            hold back for day-to-day spending (0% switches it off)
/sg look <classic|modern>   switch the info-screen look
/sg move <50s|1g>            reclassify that much 'Other' income as a transfer from your own alt
/sg reclassify <50s|1g> <from> <to>  move income between categories, e.g. /sg reclassify 50s other loot
/sg last                     show what the last gain/spend was filed as (and pending loot at the time)
/sg log                      show the last 10 activity-log entries (the source of truth)
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
