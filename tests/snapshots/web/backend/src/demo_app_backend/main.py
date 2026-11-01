from fastapi import FastAPI

app = FastAPI(title="demo-app")


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "project": "demo-app"}
