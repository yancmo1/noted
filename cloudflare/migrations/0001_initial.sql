CREATE TABLE IF NOT EXISTS sources (
  id TEXT PRIMARY KEY,
  client_recording_id TEXT UNIQUE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  original_text TEXT NOT NULL DEFAULT '',
  extracted_text TEXT NOT NULL DEFAULT '',
  source_url TEXT,
  file_key TEXT,
  mime_type TEXT,
  audio_mime_type TEXT,
  captured_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  processing_status TEXT NOT NULL DEFAULT 'pending',
  processing_error TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  summary TEXT,
  transcript_text TEXT,
  transcript_status TEXT NOT NULL DEFAULT 'pending',
  duration_ms INTEGER,
  consent_mode TEXT,
  consent_acknowledged INTEGER NOT NULL DEFAULT 0,
  recording_session_id TEXT,
  processing_version INTEGER NOT NULL DEFAULT 0,
  meeting_brief_json TEXT
);

CREATE INDEX IF NOT EXISTS sources_captured_at_idx ON sources(captured_at DESC);
CREATE INDEX IF NOT EXISTS sources_type_idx ON sources(type);

CREATE TABLE IF NOT EXISTS recording_sessions (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  duration_ms INTEGER,
  mime_type TEXT,
  client TEXT NOT NULL,
  consent_mode TEXT NOT NULL,
  consent_acknowledged INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS transcript_segments (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  segment_index INTEGER NOT NULL,
  start_ms INTEGER,
  end_ms INTEGER,
  text TEXT NOT NULL,
  speaker TEXT,
  confidence REAL,
  words_json TEXT,
  chunk_index INTEGER,
  chunk_start_ms INTEGER
);

CREATE INDEX IF NOT EXISTS transcript_segments_source_idx ON transcript_segments(source_id, segment_index);

CREATE TABLE IF NOT EXISTS chunks (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  memory_type TEXT NOT NULL,
  content TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  importance REAL NOT NULL DEFAULT 0.5,
  confidence REAL NOT NULL DEFAULT 0.7,
  status TEXT NOT NULL DEFAULT 'active',
  superseded_by TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  evidence_refs_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS memories_source_idx ON memories(source_id);
CREATE INDEX IF NOT EXISTS memories_status_idx ON memories(status, created_at DESC);

CREATE TABLE IF NOT EXISTS entities (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  canonical_name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(entity_type, canonical_name)
);

CREATE TABLE IF NOT EXISTS relationships (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  from_type TEXT NOT NULL,
  from_id TEXT NOT NULL,
  relationship_type TEXT NOT NULL,
  to_type TEXT NOT NULL,
  to_id TEXT NOT NULL,
  confidence REAL NOT NULL DEFAULT 0.7,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS open_loops (
  id TEXT PRIMARY KEY,
  memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  confidence REAL NOT NULL DEFAULT 0.7,
  due_at TEXT,
  evidence_refs_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  resolved_at TEXT
);

CREATE INDEX IF NOT EXISTS open_loops_status_idx ON open_loops(status, created_at DESC);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  next_attempt_at TEXT,
  lease_started_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(source_id, status)
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  expires_at TEXT NOT NULL
);
