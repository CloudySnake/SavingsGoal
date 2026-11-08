# Changelog

All notable changes to SavingsGoal, newest first. Version numbers match
`## Version:` in `SavingsGoal.toc`. Add an entry here on every version bump,
under the new version heading.

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
