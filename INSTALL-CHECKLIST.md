# WoW Forever — lean addon install checklist

Checked 7 Nov 2026. Client 1.60.1 / Interface 16001. Live folder is `_forever_`, not the beta `_classic_beta_` folder.

## Install first

1. In the CurseForge app, select your **WoW Forever** install (not Classic Era, not Retail).
2. For each addon below, check its Files page shows a **Forever / 1.60.1** file before installing.
3. Manual installs go in `World of Warcraft/_forever_/Interface/AddOns/` — the folder holding the `.toc` file sits directly inside `AddOns`, not nested.
4. At character select: AddOns → tick everything, and tick **Load out of date AddOns** if it asks.

## The set — 7 plus ours

- [ ] **Titan Panel 9.3.5** (15 Oct) — the bar. Needed for SavingsGoal's headline feed. If `Titan Panel [Classic]` shows as Incompatible, disable it. Don't drag plugins around — there's a known bug where they can disappear on reload.
- [ ] **SavingsGoal 1.0.0** (ours, manual install) — copy the `SavingsGoal` folder into `_forever_/Interface/AddOns/`. Titan Panel covers its libraries (LibStub, LibDataBroker-1.1, LibDBIcon-1.0). `/sg` opens it.
- [ ] **Auctionator 341** (13 Oct) — AH search, posting, shopping lists, price history. Your DE-flip tool: scan, compare green price vs mat prices, post mats.
- [ ] **Baganator** (Forever build) — one window / sorted categories, search across all characters. Needs Syndicator — CurseForge installs it automatically. Pick this *or* Bagnon, not both.
- [ ] **Aurarium** (updated 3 Nov) — account-wide gold history, per-character, by day/month. Needs Arcane Wizard Library — CurseForge installs it automatically.
- [ ] **Leatrix Plus 1.60.29-forever** (6 Nov) — QoL bundle. Everything starts off: turn on only auto-sell junk, auto-repair, faster looting. Type `/ltp`.
- [ ] **Questie Forever 12.3.1** (26 Oct) — quest givers, objectives and turn-ins on map/minimap, including quests you haven't picked up yet.
- [ ] **Vendor Price Plus** — vendor price in item tooltips, with Auctionator integration. Vendor vs AH vs DE decision at a glance.

Optional, small: **What's Training?** — what trainer skills you can buy next and what they cost. Handy levelling rogue + mage.

## Don't install (for now)

- TradeSkillMaster — heavy, and no confirmed Forever build until a claimed 5 Nov build; Auctionator covers the job.
- Auctioneer Suite / Enchantrix — no confirmed Forever DE-value tool yet; a Forever listing appeared 7 Nov, let others test it first.
- ElvUI, Details!, DBM / BigWigs, WeakAuras — bloat / not needed yet. Blizzard ships its own Damage Meter and Cooldown Manager, and combat addons are limited by Midnight's secret-values rules. Boss mods can wait until raids open 9 Dec.

## Launch-day test — 5 minutes

- [ ] All addons load, no Lua errors on login.
- [ ] `/sg` opens the SavingsGoal info screen; Titan bar shows safe-to-spend + top goal.
- [ ] Buy/sell something: income lands under the right source in SavingsGoal.
- [ ] Mail gold to the bank alt: logged as a money move, not income/spending.
- [ ] Set a goal, seed it, check the forecast math looks sane.
- [ ] Auctionator: run a scan, check a green's tooltip price.
- [ ] Baganator: search finds an item across bags/bank/alts.
- [ ] Leatrix: sell junk at a vendor, repair happens automatically.
- [ ] Aurarium: `/aur overview` shows account total and today's change.

## If something breaks

- Wrong folder is the usual cause — check it's `_forever_`, not Classic Era or `_classic_beta_`.
- After a patch, check for a newer Forever file before assuming an addon is dead.
- SavingsGoal still works without Titan Panel via `/sg` and the minimap button — the bar is display only.
