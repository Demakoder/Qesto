CREATE TABLE experiment_identity (marker text PRIMARY KEY CHECK (marker = 'qesto.synthetic-sync.v1'));
INSERT INTO experiment_identity VALUES ('qesto.synthetic-sync.v1');
CREATE TABLE workspace (
  workspace_id text PRIMARY KEY,
  owner_id text NOT NULL,
  epoch text NOT NULL,
  head bigint NOT NULL DEFAULT 0 CHECK (head >= 0),
  state text NOT NULL,
  revisions jsonb NOT NULL
);
CREATE TABLE command_receipt (
  workspace_id text NOT NULL REFERENCES workspace,
  change_id text NOT NULL,
  body_digest text NOT NULL,
  command_body text NOT NULL,
  receipt text NOT NULL,
  seq bigint NOT NULL CHECK (seq > 0),
  PRIMARY KEY (workspace_id, change_id),
  UNIQUE (workspace_id, seq)
);
CREATE TABLE change_bundle (
  workspace_id text NOT NULL REFERENCES workspace,
  seq bigint NOT NULL CHECK (seq > 0),
  change_id text NOT NULL,
  bundle text NOT NULL,
  PRIMARY KEY (workspace_id, seq),
  FOREIGN KEY (workspace_id, change_id) REFERENCES command_receipt (workspace_id, change_id),
  FOREIGN KEY (workspace_id, seq) REFERENCES command_receipt (workspace_id, seq)
);
CREATE FUNCTION immutable_record() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Immutable sync history'; END;
$$;
CREATE TRIGGER immutable_receipt BEFORE UPDATE OR DELETE ON command_receipt
FOR EACH ROW EXECUTE FUNCTION immutable_record();
CREATE TRIGGER immutable_bundle BEFORE UPDATE OR DELETE ON change_bundle
FOR EACH ROW EXECUTE FUNCTION immutable_record();
ALTER TABLE workspace ENABLE ROW LEVEL SECURITY;
ALTER TABLE command_receipt ENABLE ROW LEVEL SECURITY;
ALTER TABLE change_bundle ENABLE ROW LEVEL SECURITY;
CREATE POLICY workspace_scope ON workspace USING (workspace_id = current_setting('qesto.workspace', true));
CREATE POLICY receipt_scope ON command_receipt USING (workspace_id = current_setting('qesto.workspace', true));
CREATE POLICY bundle_scope ON change_bundle USING (workspace_id = current_setting('qesto.workspace', true));
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO qesto_sync;
GRANT SELECT ON experiment_identity TO qesto_sync;
GRANT SELECT, UPDATE ON workspace TO qesto_sync;
GRANT SELECT, INSERT ON command_receipt, change_bundle TO qesto_sync;
