from __PACKAGE_NAME___backend.main import ScoreRequest, game_state, health, submit_score


def test_health() -> None:
    assert health() == {"status": "ok", "project": "__PROJECT_NAME__"}


def test_game_state() -> None:
    assert game_state() == {"status": "ready", "project": "__PROJECT_NAME__"}


def test_submit_score() -> None:
    assert submit_score(ScoreRequest(score=42)) == {"score": 42}
