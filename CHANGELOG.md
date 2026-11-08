# Changelog

All notable changes to SavingsGoal, newest first. Version numbers match
`## Version:` in `SavingsGoal.toc`. Add an entry here on every version bump,
under the new version heading.

## [1.0.27] - 2026-11-08
### Added
- Quick-add riding presets on the main screen: one-click buttons for "Lvl 40 Riding - 100g" and "Lvl 60 Riding - 1000g" that create the goal immediately (default 100% rate). A preset hides once you already have a goal with that name, so it can't be added twice; the whole row disappears once both are taken.

## [1.0.26] - 2026-11-08
### Changed
- Goal row on the main screen now shows the saved amount with more detail when it is small: silver and copper under 1g (`45s 30c`), gold and silver under 10g (`5g 30s`), gold only at 10g and up (`25g`). Hovering the goal's progress bar shows a tooltip with the full saved and target amounts. The Titan Panel display is unchanged.

## [1.0.25] - 2026-11-08
### Changed
- Release workflow is now tag-driven: it runs when a version tag is pushed (`git tag 1.0.25 && git push origin 1.0.25`), instead of on every merge to main. Merging to main no longer deploys anything by itself — you release when you tag. The workflow reads the version from the tag and fails if it does not match the `.toc` version, and the tag-on-HEAD step is gone (the tag that starts the run is already there). This also fixes the release type: 1.0.24 went up as an Alpha file because the packager only calls a file a Release when HEAD is tagged with a clean version, and tagging after packaging left HEAD untagged at packaging time. Same addon code as 1.0.24, re-released as a Release.

## [1.0.24] - 2026-11-08
### Fixed
- Release workflow: the packager skipped the upload with "Found future tag" because the workflow created the tag on HEAD before packaging, and the packager treats a tagged HEAD on a branch push as a duplicate build (it expects the real build to come from the tag push). The workflow no longer tags before packaging: it passes the version from the `.toc` to the packager directly (`-n`), uploads, and only then creates the tag for the record. (1.0.23 merged and was tagged, but no file reached CurseForge, so 1.0.23 is skipped; 1.0.24 is the first version the automated deploy will publish.)

## [1.0.23] - 2026-11-08
### Fixed
- Release workflow: the "CF_API_KEY secret is missing" check used `secrets` in an `if:` expression, which GitHub rejects — the secret is now checked via an environment variable instead. (1.0.22 merged but its deploy never ran because the workflow file itself was invalid; 1.0.23 is the first version the automated deploy will publish.)

## [1.0.22] - 2026-11-08
### Added
- CurseForge release automation: a GitHub Actions workflow deploys to CurseForge on every merge to main, tagging the release from the `.toc` version automatically. Packaging config (`.pkgmeta`) and this changelog.

## [1.0.21] - 2026-11-08
### Changed
- `/sg seed` now accepts silver (`/sg seed Mount 40s`, `1g 50s`); a plain number still means gold. The UI seed popup still takes gold only.

## [1.0.20] - 2026-11-07
### Fixed
- Repairs now file correctly: the repair cost is read at the money change itself (a drop in the repair cost confirms a repair), splitting a batched repair+purchase. Fixes Leatrix auto-repair being filed as vendor.

## [1.0.19] - 2026-11-07
### Added
- Diagnostic only: `/sg log` now shows the pending repair cost beside each money change, to pin down the repair misfile.

## [1.0.18] - 2026-11-07
### Added
- Cursor repairs (durability baseline at merchant open), taxi fares (TakeTaxiNode hook), barber / transmog / talent / Dungeon Finder categories, and cash-on-delivery mail.

## [1.0.17] - 2026-11-07
### Fixed
- Audit fixes: outgoing moves match largest-fit (not exact), and the repair flag expires 5s after the click.

## [1.0.16] - 2026-11-07
### Added
- Auction House sales are now detected by mail subject as well as sender; batched mail matching (exact first, then largest fitting); the mailbox is scanned on open; `/sg mail` diagnostic.

## [1.0.15] - 2026-11-07
### Added
- Trainer, taxi (window), trade, bank, outbid-refund reversal, quest rewards by exact amount, stale-loot expiry.

## [1.0.14] - 2026-11-07
### Added
- Auction House listing fees; `/sg reclassify` extended to spending.

## [1.0.13] - 2026-11-07
### Added
- Loot-window coin scan, chat via message filter, and the activity log (`/sg log` prints the last 10).

## [1.0.12] - 2026-11-07
### Changed
- `/sg last` reports the final filing; late-chat window extended from 3s to 10s.

## [1.0.11] - 2026-11-07
### Added
- Repairs category (via the RepairAllItems hook).

## [1.0.10] - 2026-11-07
### Added
- `/sg reclassify <amount> <from> <to>` and `/sg last`.

## [1.0.9] - 2026-11-07
### Added
- Loot accumulation/split and late-chat reclassify; mail fees category; `SpendingBySource()`.

## [1.0.8] - 2026-11-07
### Fixed
- Mail to a bank alt no longer misfiles: own-character names matched case-insensitively, outgoing-moves ledger, `/sg move`.

## [1.0.7] - 2026-11-07
### Fixed
- Modern look clipping fix.

## [1.0.6] - 2026-11-07
### Added
- Modern look, with a Classic/Modern toggle.

## [1.0.5] - 2026-11-07
### Changed
- UI polish.

## [1.0.4] - 2026-11-07
### Added
- Per-character safe-to-spend.
