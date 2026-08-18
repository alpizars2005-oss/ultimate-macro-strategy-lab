from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STABLE = ROOT / "channel" / "stable" / "files"


def read(name: str) -> str:
    return (STABLE / name).read_text(encoding="utf-8-sig")


def test_strategy_reader_accepts_utf16_and_reports_encoding():
    validation = read("lib__StrategyLab__LabStrategyValidation.ahk")
    assert "LabStrategyReadText" in validation
    assert 'FileRead(path, "UTF-16")' in validation
    assert 'encoding := "UTF-16"' in validation
    assert "embedded NUL bytes" in validation


def test_editor_preserves_detected_strategy_encoding():
    core = read("lib__StrategyLab__StrategyEditorCore.ahk")
    assert "LabStrategyReadText(path, &this.Encoding)" in core
    assert "FileAppend(this.RenderText(), path, this.Encoding)" in core
    assert "FileAppend(this.RenderText(), temp, this.Encoding)" in core


def test_webhook_title_opens_remote_settings():
    preflight = read("submacros__lab_preflight.ps1")
    assert "Install-WebhookRemoteShortcut" in preflight
    assert 'Tab4_Title.OnEvent(\"Click\", LabRemoteLaunchSettings)' in preflight
    assert "Discord Webhook title -> Strategy Lab Remote settings shortcut" in preflight


def test_remote_settings_has_visible_failure_diagnostics():
    remote = read("submacros__lab_remote_settings.ps1")
    assert "remote-settings.log" in remote
    assert "Show-Fatal" in remote
    assert "FATAL remote settings startup" in remote
    assert "Save + Start" in remote


def test_remote_start_matches_upstream_startstrategy_arity():
    gate = read("lib__StrategyLab__LabRemoteGate.ahk")
    assert "StartStrategy(0, 0)" in gate
    safety = read("lib__StrategyLab__LabSafety.ahk")
    assert "StopStrategy(0, 0)" in safety
