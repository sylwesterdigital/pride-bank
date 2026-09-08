-- Make Stripe webhook processing retry-safe and concurrency-safe.
-- A delivery is only a duplicate after processed_at is set. Failed attempts clear
-- their processing claim so Stripe retries can settle the same event again.

ALTER TABLE stripe_webhook_events
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz;

ALTER TABLE stripe_webhook_events
  ADD COLUMN IF NOT EXISTS processing_attempts integer NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS stripe_webhook_events_pending_idx
  ON stripe_webhook_events (processing_started_at)
  WHERE processed_at IS NULL;
