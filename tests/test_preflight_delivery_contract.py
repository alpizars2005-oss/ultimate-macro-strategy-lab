from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = ROOT / "channel/stable/files/submacros__lab_preflight.ps1"
FILES_MAP = ROOT / "channel/stable/files.map"


def _delivery_targets() -> set[str]:
    targets: set[str] = set()
    for raw in FILES_MAP.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        target, _source, _mode = [part.strip() for part in line.split("|")]
        targets.add(target.replace("\\", "/"))
    return targets


def _preflight_required_modules() -> set[str]:
    text = PREFLIGHT.read_text(encoding="utf-8-sig")
    match = re.search(
        r"function\s+Verify-LabModules\b.*?\$required\s*=\s*@\((.*?)\)\s*\n\s*\$missing",
        text,
        flags=re.S,
    )
    assert match, "could not locate Verify-LabModules $required array"
    return {
        value.replace("\\", "/")
        for value in re.findall(r"'([^']+)'", match.group(1))
    }


def test_preflight_only_requires_files_delivered_by_stable_channel():
    targets = _delivery_targets()
    required = _preflight_required_modules()
    missing = sorted(required - targets)
    assert not missing, f"preflight requires files that stable does not deliver: {missing}"


def test_preflight_uses_current_single_canvas_map_module():
    required = _preflight_required_modules()
    assert "lib/StrategyLab/StrategyEditorMaps046.ahk" in required
    assert "lib/StrategyLab/StrategyEditorMaps.ahk" not in required
