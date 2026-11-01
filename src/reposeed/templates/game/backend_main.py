from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI(title="__PROJECT_NAME__")


class ScoreRequest(BaseModel):
    score: int = Field(ge=0)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "project": "__PROJECT_NAME__"}


@app.get("/api/game/state")
def game_state() -> dict[str, str]:
    return {"status": "ready", "project": "__PROJECT_NAME__"}


@app.post("/api/game/score")
def submit_score(score: ScoreRequest) -> dict[str, int]:
    return {"score": score.score}
