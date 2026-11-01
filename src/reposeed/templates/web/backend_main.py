from fastapi import FastAPI

app = FastAPI(title="__PROJECT_NAME__")


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "project": "__PROJECT_NAME__"}
