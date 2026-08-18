from pathlib import Path


def stable_text(name: str) -> str:
    path = Path("channel/stable/files") / name
    return path.read_text(encoding="utf-8-sig")


def test_strategy_editor_does_not_pass_object_property_byref():
    core = stable_text("lib__StrategyLab__StrategyEditorCore.ahk")
    assert "&this." not in core
    assert 'detectedEncoding := ""' in core
    assert "LabStrategyReadText(path, &detectedEncoding)" in core
    assert "this.Encoding := detectedEncoding" in core


def test_upstream_start_stop_are_called_with_required_control_arg():
    safety = stable_text("lib__StrategyLab__LabSafety.ahk")
    remote = stable_text("lib__StrategyLab__LabRemoteGate.ahk")
    assert "StopStrategy(0, 0)" in safety
    assert "StartStrategy(0, 0)" in remote
