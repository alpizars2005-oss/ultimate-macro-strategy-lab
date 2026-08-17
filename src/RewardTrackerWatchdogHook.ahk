#Requires AutoHotkey v2.0
#Include "RewardTrackerCore.ahk"

; Integration sketch for Ultimate Macro's result watchdog.
; This file deliberately does not include or replace watchdog.ahk yet.
;
; Intended call site: after a Triumph has been claimed/deduplicated and a stable
; result anchor (Play Again / Restart) is available, before the next run starts.

RewardTrackerOnConfirmedTriumph(runId, mapName, modeName, foundX, foundY, clientW, clientH) {
    result := {confirmed: [], unknownEvidence: ""}

    ; Existing base currency readers can feed confirmed observations directly:
    ; RewardTrackerAppend(runId, mapName, modeName, "coins", "Coins", coinVal, 1.0, "result-ocr")
    ; RewardTrackerAppend(runId, mapName, modeName, "gems", "Gems", gemVal, 1.0, "result-ocr")
    ; RewardTrackerAppend(runId, mapName, modeName, "xp", "XP", expVal, 1.0, "result-ocr")
    ;
    ; Item scanning is intentionally left to the macro integration layer because it
    ; already owns GDI+, AdvImageSearch and OCR. The planned sequence is:
    ;   1. capture a broad result/reward region relative to foundX/foundY;
    ;   2. search registered icon templates (duck, crate_*, consumable_*);
    ;   3. OCR a bounded quantity crop next to each icon;
    ;   4. RewardTrackerAcceptCandidate(candidate);
    ;   5. RewardTrackerAppend(...);
    ;   6. save one evidence crop if an unknown card remains.
    ;
    ; Keeping the integration outside this core makes it easy to calibrate templates
    ; from real TDS result screenshots without touching the ledger implementation.

    return result
}
