-- Harden the Blocks ledger at the database boundary. The API role can read the
-- ledger but cannot directly forge ledger entries or mutate balances.

-- Normalize ownership for installations upgraded from v0.3.1, where the
-- application login role may have owned the schema objects.
ALTER TABLE users OWNER TO pride_owner;
ALTER TABLE auth_sessions OWNER TO pride_owner;
ALTER TABLE blocks_accounts OWNER TO pride_owner;
ALTER TABLE ledger_transactions OWNER TO pride_owner;
ALTER TABLE ledger_entries OWNER TO pride_owner;
ALTER TABLE stripe_topups OWNER TO pride_owner;
ALTER TABLE stripe_webhook_events OWNER TO pride_owner;
ALTER TABLE account_security_events OWNER TO pride_owner;
ALTER TABLE schema_migrations OWNER TO pride_owner;
ALTER FUNCTION post_member_transfer(uuid,uuid,bigint,text,text) OWNER TO pride_owner;
ALTER FUNCTION post_topup_credit(uuid,bigint,text,uuid) OWNER TO pride_owner;
ALTER FUNCTION post_topup_reversal(uuid,bigint,text,uuid) OWNER TO pride_owner;
ALTER FUNCTION ledger_immutable() OWNER TO pride_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM pride_app;

CREATE OR REPLACE FUNCTION assert_ledger_transaction_balanced()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total bigint;
BEGIN
  SELECT COALESCE(sum(amount),0) INTO total FROM ledger_entries WHERE transaction_id=NEW.transaction_id;
  IF total <> 0 THEN RAISE EXCEPTION 'ledger transaction % is not balanced (sum=%)', NEW.transaction_id, total; END IF;
  RETURN NULL;
END $$;

ALTER FUNCTION assert_ledger_transaction_balanced() OWNER TO pride_owner;

CREATE OR REPLACE FUNCTION create_member_blocks_account(p_user uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE account_id uuid;
BEGIN
  INSERT INTO blocks_accounts (user_id, account_type, label)
  VALUES (p_user, 'member', 'Blocks')
  RETURNING id INTO account_id;
  RETURN account_id;
END $$;
ALTER FUNCTION create_member_blocks_account(uuid) OWNER TO pride_owner;

DROP TRIGGER IF EXISTS ledger_entries_balanced ON ledger_entries;
CREATE CONSTRAINT TRIGGER ledger_entries_balanced
AFTER INSERT ON ledger_entries DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_ledger_transaction_balanced();

ALTER FUNCTION post_member_transfer(uuid,uuid,bigint,text,text) SECURITY DEFINER;
ALTER FUNCTION post_topup_credit(uuid,bigint,text,uuid) SECURITY DEFINER;
ALTER FUNCTION post_topup_reversal(uuid,bigint,text,uuid) SECURITY DEFINER;
ALTER FUNCTION post_member_transfer(uuid,uuid,bigint,text,text) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION post_topup_credit(uuid,bigint,text,uuid) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION post_topup_reversal(uuid,bigint,text,uuid) SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON ledger_transactions, ledger_entries FROM PUBLIC;
REVOKE ALL ON ledger_transactions, ledger_entries FROM pride_app;
GRANT SELECT ON ledger_transactions, ledger_entries TO pride_app;
GRANT EXECUTE ON FUNCTION post_member_transfer(uuid,uuid,bigint,text,text) TO pride_app;
GRANT EXECUTE ON FUNCTION post_topup_credit(uuid,bigint,text,uuid) TO pride_app;
GRANT EXECUTE ON FUNCTION post_topup_reversal(uuid,bigint,text,uuid) TO pride_app;

REVOKE ALL ON blocks_accounts FROM pride_app;
GRANT SELECT ON blocks_accounts TO pride_app;
GRANT EXECUTE ON FUNCTION create_member_blocks_account(uuid) TO pride_app;

GRANT SELECT, INSERT, UPDATE ON users, auth_sessions, stripe_topups, stripe_webhook_events, account_security_events TO pride_app;
GRANT DELETE ON auth_sessions TO pride_app;
GRANT USAGE ON SCHEMA public TO pride_app;
