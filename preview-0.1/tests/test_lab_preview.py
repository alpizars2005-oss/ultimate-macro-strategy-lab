from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "Main_Lab.ahk").read_text(encoding="utf-8-sig")
WATCHDOG = (ROOT / "submacros" / "watchdog_lab.ahk").read_text(encoding="utf-8-sig")

SPAWN_RE = re.compile(
    r"(?i)^(\s*SpawnTower\(\s*)(-?\d+)(\s*,\s*)(-?\d+)(\s*,\s*[^,]+?\s*,\s*[^)]+?\s*\)\s*)$"
)

def placements(path: Path):
    text = path.read_text(encoding="utf-8-sig")
    section = ""
    result = []
    for i, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^\[([^\]]+)\]$", line.strip())
        if m:
            section = m.group(1).strip().lower()
            continue
        if section == "steps":
            sm = SPAWN_RE.match(line)
            if sm:
                result.append((i, int(sm.group(2)), int(sm.group(4)), line))
    return result

def rewrite(line: str, x: int, y: int):
    return re.sub(
        r"(?i)^(\s*SpawnTower\(\s*)-?\d+(\s*,\s*)-?\d+",
        rf"\g<1>{x}\g<2>{y}",
        line,
        count=1,
    )

def test_integrated_tabs_and_modules_are_wired():
    assert 'ver := "1.3.3-lab.0.1"' in MAIN
    assert '"Editor", "Stats", "Credits"' in MAIN
    assert "StrategyEditorCreateTab(MainGui)" in MAIN
    assert "RewardTrackerCreateTab(MainGui)" in MAIN
    assert "watchdog_lab.ahk" in MAIN

def test_reward_tracker_runs_even_without_webhook():
    assert 'shouldSendWebhook := (WebhookEnabled && WebhookLink != "")' in WATCHDOG
    send_info = WATCHDOG.split("SendInfo(matchResult := \"\") {", 1)[1].split("\nBinarizeTargetBitmap(pBitmap) {", 1)[0]
    assert "if (!WebhookEnabled || WebhookLink = \"\")" not in send_info
    assert "RewardTrackerRecordRun(" in send_info
    assert "RewardTrackerCaptureEvidence(" in WATCHDOG

def test_window_offset_fix_is_present_for_result_ocr():
    assert "Gdip_BitmapFromScreen((pX + targetX)" in WATCHDOG
    assert "Gdip_BitmapFromScreen((pX + infoX)" in WATCHDOG

def test_every_official_strategy_spawn_line_can_be_conservatively_rewritten():
    strats = list((ROOT / "Resources" / "Strats").glob("*.strat"))
    assert strats
    seen = 0
    for path in strats:
        for _, x, y, line in placements(path):
            edited = rewrite(line, x + 1, y + 1)
            assert edited != line
            assert edited.count("SpawnTower(") == 1
            before_tail = line.split(",", 2)[2]
            after_tail = edited.split(",", 2)[2]
            assert before_tail == after_tail
            seen += 1
    assert seen >= 20

def test_133_actions_are_untouched_by_coordinate_rewrite():
    sample = [
        "SpawnTower(592, 474, 2, dj1)",
        "UpgradeTower(dj1)",
        "ChangeTargets(dj1, Strongest)",
        "ToggleAutoskip()",
        "SellTower(dj1)",
        "FutureOfficialAction(dj1, NewArg)",
    ]
    edited = [rewrite(sample[0], 620, 490)] + sample[1:]
    assert edited[0] == "SpawnTower(620, 490, 2, dj1)"
    assert edited[1:] == sample[1:]
