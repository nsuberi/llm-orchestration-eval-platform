from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, Any

app = FastAPI(title="CTB API")

# Enable permissive CORS for local/dev usage so the browser at
# http://localhost:3000 can call the API (e.g., http://localhost:8000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/healthz")
def healthz():
    return {"ok": True}

@app.get("/metrics/sample")
def sample_metrics():
    return {"latency_ms_p95": 1234, "cost_cents": 42}


class RunRequest(BaseModel):
    graph_version_id: str
    dataset_id: str
    config: Dict[str, Any] | None = None
    phi_mode: str | None = None


@app.post("/api/runs")
def create_run(req: RunRequest):
    # Stub: return a fake run id
    return {"run_id": "run_123", "status": "queued"}


@app.get("/api/run_items/{item_id}")
def get_run_item(item_id: str):
    # Stub: return a minimal payload matching the contract
    return {
        "id": item_id,
        "note_json": {"sections": [{"title": "Assessment", "text": "Type 2 DM."}]},
        "evidence_links": [
            {
                "note_span": [120, 168],
                "src": "transcript",
                "src_span": [932, 1001],
                "conf": 0.92,
            }
        ],
        "eval": {"support": 0.88, "schema_ok": True},
    }
