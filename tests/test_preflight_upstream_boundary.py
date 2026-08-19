from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = ROOT / "channel/stable/files/submacros__lab_preflight.ps1"
RUNTIME_TEST = ROOT / "tests/preflight_runtime_patch_test.ps1"


def test_capture_anchor_matches_real_runstrategy_flow():
    text = PREFLIGHT.read_text(encoding="utf-8-sig")
    assert "activateTimescale\\(\\)" in text
    assert "pre-activateTimescale" in text
    assert "post-LoadGame anchor" not in text
    assert "LoadGame\\(\\)" not in text


def test_runtime_fixture_has_real_camera_to_play_order():
    text = RUNTIME_TEST.read_text(encoding="utf-8-sig")
    expected = [
        "AlignCamera()",
        "CheckTheMapF()",
        "activateTimescale()",
        "ClickReady()",
        "PlayStrategy()",
        "i := 1",
    ]
    positions = [text.index(token) for token in expected]
    assert positions == sorted(positions)
    assert "There is deliberately NO LoadGame() call inside RunStrategy()." in text
