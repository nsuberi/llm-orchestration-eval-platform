-- Minimal Postgres schema matching the proposed data model
CREATE TABLE IF NOT EXISTS datasets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  modality TEXT,
  source TEXT,
  phi_state TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS datapoints (
  id TEXT PRIMARY KEY,
  dataset_id TEXT REFERENCES datasets(id),
  transcript_uri TEXT,
  audio_uri TEXT,
  emr_context_jsonb JSONB,
  ground_truth_jsonb JSONB,
  tags TEXT[]
);

CREATE TABLE IF NOT EXISTS graphs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  yaml TEXT NOT NULL,
  inputs_schema JSONB,
  outputs_schema JSONB,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS graph_versions (
  id TEXT PRIMARY KEY,
  graph_id TEXT REFERENCES graphs(id),
  semver TEXT,
  prompt_hash TEXT,
  toolset_hash TEXT,
  model_manifest_jsonb JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  graph_version_id TEXT REFERENCES graph_versions(id),
  dataset_id TEXT REFERENCES datasets(id),
  run_config_jsonb JSONB,
  status TEXT,
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  cost_cents INTEGER,
  latency_ms_p50 INTEGER,
  latency_ms_p95 INTEGER
);

CREATE TABLE IF NOT EXISTS run_items (
  id TEXT PRIMARY KEY,
  run_id TEXT REFERENCES runs(id),
  datapoint_id TEXT REFERENCES datapoints(id),
  status TEXT,
  outputs_jsonb JSONB,
  eval_jsonb JSONB,
  evidence_links_jsonb JSONB,
  tokens_in INTEGER,
  tokens_out INTEGER,
  cost_cents INTEGER,
  latency_ms INTEGER,
  model_trace_uri TEXT
);

CREATE TABLE IF NOT EXISTS evidence_links (
  id TEXT PRIMARY KEY,
  run_item_id TEXT REFERENCES run_items(id),
  note_span_start INTEGER,
  note_span_end INTEGER,
  source_type TEXT CHECK (source_type IN ('audio','text')),
  source_span_start INTEGER,
  source_span_end INTEGER,
  confidence REAL
);

CREATE TABLE IF NOT EXISTS metrics (
  id TEXT PRIMARY KEY,
  run_id TEXT REFERENCES runs(id),
  key TEXT,
  value REAL,
  scope TEXT CHECK (scope IN ('run','item','cohort'))
);

CREATE TABLE IF NOT EXISTS audits (
  id TEXT PRIMARY KEY,
  entity_type TEXT,
  entity_id TEXT,
  action TEXT,
  actor TEXT,
  diff_jsonb JSONB,
  ts TIMESTAMPTZ DEFAULT now()
);
