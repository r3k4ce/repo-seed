from demo_app_backend.main import ScoreRequest, game_state, health, submit_score


def test_health() -> None:
    assert health() == {"status": "ok", "project": "demo-app"}


def test_game_state() -> None:
    assert game_state() == {"status": "ready", "project": "demo-app"}


def test_submit_score() -> None:
    assert submit_score(ScoreRequest(score=42)) == {"score": 42}
