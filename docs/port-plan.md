# Selective Kronox port plan

Baseline: **Darksen official Ultimate Macro 1.3.3**.

Kronox is treated as a source of useful implementation ideas, not as the new base. Every candidate is adapted onto 1.3.3 and tested independently.

## Port matrix

| Candidate | Priority | Lab status | Integration rule |
|---|---:|---|---|
| Input failsafe / release held input on recovery | High | Planned | Recovery boundary only; never alter recorded action timing |
| Phase + heartbeat stall recovery | High | Planned | Watchdog/lifecycle only |
| Append-only run ledger | High | Planned with Reward Tracker | One confirmed result = one ledger event; never guess a loss |
| Strategy fingerprint/version attribution | High | Planned | Hash/source metadata only; no gameplay mutation |
| Strategy profiler | High | Planned | Measure around actions without changing their semantics |
| Editor Save Copy + timestamped backup | High | Prototype implemented | Keep official 1.3.3 text intact except requested edit |
| Hotbar/layer editor UX | High | Prototype in progress | Visual/editor-only feature |
| Reward-card recognition pattern | High | Prototype in progress | Result screen only; template + bounded OCR + fail closed |
| Tower XP tracking concepts | Medium | Researching | Optional; result screen only |
| Strategy library filtering/favorites | Medium | Candidate | UI-only; no automatic destructive updates |
| Abstract multi-slot support | Medium | Dedicated testing later | Must preserve official abstract semantics |
| Evolution queue | Medium | Dedicated testing later | Separate opt-in module |
| Advanced skip-wave policy | Medium | Dedicated testing later | Must coexist with official 1.3.3 `ToggleAutoskip()` |
| Resource-budget guards | Medium | Dedicated testing later | No hidden gameplay clicks |
| Boost-aware analytics / ROI | Low | Later | Analytics only |
| TDS update canary | Low | Later | Informational/fail-safe, never destructive updater behavior |
| Kronox updater/repository routing | Never transplant | Rejected | Official updater ownership remains upstream |
| Whole-file Kronox `Main.ahk` merge | Never transplant | Rejected | Too risky and would overwrite newer 1.3.3 behavior |

## High-value candidates in more detail

### 1. Input failsafe

Borrow the reliability concept: on a confirmed runtime/watchdog failure, stop automation timers and release held keys/buttons before recovery. The implementation must live outside strategy timing loops.

### 2. Phase/heartbeat recovery

Track coarse lifecycle phases such as lobby launch, map voting, match setup, playback, result handling, and safe recovery. Use phase-specific deadlines instead of one blind timeout. Do not add heartbeat checks to recorded steps themselves.

### 3. Trustworthy analytics

Use an append-only run ledger with strategy fingerprinting. A result should be recorded only when evidence exists. Missing/aborted attempts remain unknown/aborted rather than being silently counted as losses.

### 4. Strategy profiler

Collect duration/retry/failure telemetry for actions while preserving the exact official action calls. The profiler observes; it does not rewrite strategy timing.

### 5. Editor safety and hotbar UX

Reuse the good concepts from Kronox's editor—layer/hotbar awareness, safe copies/backups, preserving untouched steps—but extend them into the visual 1920x1080 drag editor requested for this lab.

### 6. Reward recognition

Use the same general reliability pattern as robust result-card readers: icon/template evidence plus OCR only over a tiny known quantity region, confidence rules, and `UNKNOWN` evidence capture rather than guessing.

## Official 1.3.3 compatibility rule

The visual editor rewrites only coordinate tokens inside a selected `SpawnTower(...)` line. Newer official actions such as `ChangeTargets(...)` and `ToggleAutoskip()` must remain untouched. Unknown future steps must also survive because the editor does not regenerate the `[Steps]` block.

## Do not blindly transplant

- whole-file `Main.ahk` replacements;
- fork updater behavior or repository routing;
- fork branding;
- any code that polls, OCRs, or clicks inside `PlayStrategy()` / recorded timing paths;
- any automation that converts an ambiguous result into a guessed reward or guessed loss.
