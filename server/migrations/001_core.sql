CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  username text NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text NOT NULL,
  password_hash text NOT NULL,
  stripe_customer_id text UNIQUE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','frozen','closed')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions(user_id);

CREATE TABLE blocks_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE RESTRICT,
  account_type text NOT NULL CHECK (account_type IN ('member','system_issuance','system_sink')),
  label text NOT NULL,
  balance bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','frozen','closed')),
  allow_negative boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, account_type)
);
CREATE UNIQUE INDEX blocks_system_type_unique ON blocks_accounts(account_type) WHERE user_id IS NULL;
INSERT INTO blocks_accounts(user_id,account_type,label,allow_negative) VALUES
  (NULL,'system_issuance','Blocks issuance',true),
  (NULL,'system_sink','Blocks sink',true)
ON CONFLICT DO NOTHING;

CREATE TABLE ledger_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL,
  description text NOT NULL DEFAULT '',
  external_reference text UNIQUE,
  idempotency_key text UNIQUE,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL REFERENCES ledger_transactions(id) ON DELETE RESTRICT,
  account_id uuid NOT NULL REFERENCES blocks_accounts(id) ON DELETE RESTRICT,
  amount bigint NOT NULL CHECK (amount <> 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(transaction_id, account_id)
);
CREATE INDEX ledger_entries_account_created_idx ON ledger_entries(account_id,created_at DESC);

CREATE TABLE stripe_topups (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  package_id text NOT NULL,
  blocks_amount bigint NOT NULL CHECK (blocks_amount > 0),
  fiat_amount bigint NOT NULL CHECK (fiat_amount > 0),
  currency text NOT NULL CHECK (currency ~ '^[a-z]{3}$'),
  stripe_payment_intent_id text NOT NULL UNIQUE,
  request_key text NOT NULL,
  status text NOT NULL CHECK (status IN ('pending','succeeded','failed','canceled','refunded')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE(user_id,request_key)
);

CREATE TABLE stripe_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stripe_event_id text NOT NULL UNIQUE,
  event_type text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  processing_error text
);

CREATE TABLE account_security_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  kind text NOT NULL,
  reference text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id,kind,reference)
);

CREATE OR REPLACE FUNCTION post_member_transfer(p_from_user uuid,p_to_user uuid,p_amount bigint,p_note text,p_idempotency text)
RETURNS TABLE(transaction_id uuid, sender_balance bigint) LANGUAGE plpgsql AS $$
DECLARE from_acc blocks_accounts%ROWTYPE; to_acc blocks_accounts%ROWTYPE; txid uuid;
BEGIN
  IF p_amount <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;
  SELECT * INTO from_acc FROM blocks_accounts WHERE user_id=p_from_user AND account_type='member' FOR UPDATE;
  SELECT * INTO to_acc FROM blocks_accounts WHERE user_id=p_to_user AND account_type='member' FOR UPDATE;
  IF from_acc.id IS NULL OR to_acc.id IS NULL THEN RAISE EXCEPTION 'account missing'; END IF;
  IF from_acc.status <> 'active' OR to_acc.status <> 'active' THEN RAISE EXCEPTION 'account unavailable'; END IF;
  SELECT id INTO txid FROM ledger_transactions WHERE idempotency_key=p_idempotency;
  IF txid IS NOT NULL THEN RETURN QUERY SELECT txid,from_acc.balance; RETURN; END IF;
  IF from_acc.balance < p_amount THEN RAISE EXCEPTION 'insufficient Blocks'; END IF;
  INSERT INTO ledger_transactions(kind,description,idempotency_key,metadata) VALUES('member_transfer',left(coalesce(p_note,''),180),p_idempotency,jsonb_build_object('from_user',p_from_user,'to_user',p_to_user)) RETURNING id INTO txid;
  INSERT INTO ledger_entries(transaction_id,account_id,amount) VALUES(txid,from_acc.id,-p_amount),(txid,to_acc.id,p_amount);
  UPDATE blocks_accounts SET balance=balance-p_amount WHERE id=from_acc.id RETURNING balance INTO from_acc.balance;
  UPDATE blocks_accounts SET balance=balance+p_amount WHERE id=to_acc.id;
  RETURN QUERY SELECT txid,from_acc.balance;
END $$;

CREATE OR REPLACE FUNCTION post_topup_credit(p_user uuid,p_amount bigint,p_payment_intent text,p_topup uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE member blocks_accounts%ROWTYPE; issuance blocks_accounts%ROWTYPE; txid uuid;
BEGIN
  SELECT * INTO member FROM blocks_accounts WHERE user_id=p_user AND account_type='member' FOR UPDATE;
  SELECT * INTO issuance FROM blocks_accounts WHERE user_id IS NULL AND account_type='system_issuance' FOR UPDATE;
  SELECT id INTO txid FROM ledger_transactions WHERE external_reference=p_payment_intent;
  IF txid IS NOT NULL THEN RETURN txid; END IF;
  INSERT INTO ledger_transactions(kind,description,external_reference,metadata) VALUES('blocks_topup','Add Blocks',p_payment_intent,jsonb_build_object('stripe_payment_intent',p_payment_intent,'topup_id',p_topup)) RETURNING id INTO txid;
  INSERT INTO ledger_entries(transaction_id,account_id,amount) VALUES(txid,issuance.id,-p_amount),(txid,member.id,p_amount);
  UPDATE blocks_accounts SET balance=balance-p_amount WHERE id=issuance.id;
  UPDATE blocks_accounts SET balance=balance+p_amount WHERE id=member.id;
  RETURN txid;
END $$;

CREATE OR REPLACE FUNCTION post_topup_reversal(p_user uuid,p_amount bigint,p_payment_intent text,p_topup uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE member blocks_accounts%ROWTYPE; sink blocks_accounts%ROWTYPE; txid uuid; ref text;
BEGIN
  ref := p_payment_intent || ':refund';
  SELECT * INTO member FROM blocks_accounts WHERE user_id=p_user AND account_type='member' FOR UPDATE;
  SELECT * INTO sink FROM blocks_accounts WHERE user_id IS NULL AND account_type='system_sink' FOR UPDATE;
  SELECT id INTO txid FROM ledger_transactions WHERE external_reference=ref;
  IF txid IS NOT NULL THEN RETURN txid; END IF;
  INSERT INTO ledger_transactions(kind,description,external_reference,metadata) VALUES('topup_reversal','Stripe refund',ref,jsonb_build_object('stripe_payment_intent',p_payment_intent,'topup_id',p_topup)) RETURNING id INTO txid;
  INSERT INTO ledger_entries(transaction_id,account_id,amount) VALUES(txid,member.id,-p_amount),(txid,sink.id,p_amount);
  UPDATE blocks_accounts SET balance=balance-p_amount,status='frozen' WHERE id=member.id;
  UPDATE blocks_accounts SET balance=balance+p_amount WHERE id=sink.id;
  RETURN txid;
END $$;

CREATE OR REPLACE FUNCTION ledger_immutable() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'ledger rows are immutable'; END $$;
CREATE TRIGGER ledger_transactions_no_update BEFORE UPDATE OR DELETE ON ledger_transactions FOR EACH ROW EXECUTE FUNCTION ledger_immutable();
CREATE TRIGGER ledger_entries_no_update BEFORE UPDATE OR DELETE ON ledger_entries FOR EACH ROW EXECUTE FUNCTION ledger_immutable();
