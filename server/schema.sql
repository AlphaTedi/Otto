-- Otto telemetry (docs/TELEMETRY.md). No column holds user-written text.
CREATE TABLE IF NOT EXISTS installs (
  install_id TEXT PRIMARY KEY,
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  first_version TEXT,
  last_version TEXT,
  os TEXT,
  lang TEXT,
  layout TEXT,
  env TEXT
);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY,
  install_id TEXT NOT NULL,
  session_id TEXT,
  name TEXT NOT NULL,
  props TEXT,
  app_version TEXT,
  ts TEXT NOT NULL,
  day TEXT NOT NULL,
  received_at TEXT NOT NULL,
  env TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS events_name_day ON events(name, day);
CREATE INDEX IF NOT EXISTS events_install_ts ON events(install_id, ts);
CREATE INDEX IF NOT EXISTS events_day ON events(day);

-- Kept forever, so trends outlive the 90-day raw retention.
CREATE TABLE IF NOT EXISTS daily_rollups (
  day TEXT NOT NULL,
  metric TEXT NOT NULL,
  dim TEXT NOT NULL DEFAULT '',
  value REAL NOT NULL,
  PRIMARY KEY (day, metric, dim)
);
