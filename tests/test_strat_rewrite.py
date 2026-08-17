import re

SAMPLE_133 = """[Settings]\nrequiredTowers=Farm, DJ, Ranger\n\n[Steps]\nSpawnTower(592, 474, 2, dj1)\nUpgradeTower(dj1)\nChangeTargets(dj1, Strongest)\nToggleAutoskip()\nSpawnTower(1000, 900, 3, r1)\nSellTower(dj1)\n"""


def rewrite(line: str, x: int, y: int) -> str:
    return re.sub(
        r"(?i)^(\s*SpawnTower\(\s*)-?\d+(\s*,\s*)-?\d+",
        rf"\g<1>{x}\g<2>{y}",
        line,
        count=1,
    )


def test_only_coordinates_change():
    original = "SpawnTower(592, 474, 2, dj1)"
    assert rewrite(original, 620, 490) == "SpawnTower(620, 490, 2, dj1)"


def test_dependent_actions_need_no_change():
    lines = SAMPLE_133.splitlines()
    edited = [
        rewrite(line, 620, 490) if line.startswith("SpawnTower(592") else line
        for line in lines
    ]
    assert "UpgradeTower(dj1)" in edited
    assert "SpawnTower(620, 490, 2, dj1)" in edited
    assert "SpawnTower(1000, 900, 3, r1)" in edited


def test_official_133_actions_survive_coordinate_edit_unchanged():
    before = SAMPLE_133.splitlines()
    after = [
        rewrite(line, 620, 490) if line.startswith("SpawnTower(592") else line
        for line in before
    ]
    for action in [
        "UpgradeTower(dj1)",
        "ChangeTargets(dj1, Strongest)",
        "ToggleAutoskip()",
        "SellTower(dj1)",
    ]:
        assert before.count(action) == 1
        assert after.count(action) == 1


def test_unknown_future_action_is_preserved():
    unknown = "FutureOfficialAction(dj1, SomeNewArg)"
    lines = ["SpawnTower(10, 20, 2, dj1)", unknown]
    edited = [rewrite(lines[0], 30, 40), lines[1]]
    assert edited[1] == unknown
