import crypto from 'node:crypto';
import Stripe from 'stripe';
import { config } from './config.js';
import { pool, tx } from './db.js';

export const stripe = new Stripe(config.stripeSecretKey, { appInfo: { name: 'Pride Blocks', version: '0.3.4' } });

export const packages = Object.freeze([
  { id: 'blocks_500_gbp', blocks: 500, amount: 500, currency: 'gbp', label: '500 Blocks' },
  { id: 'blocks_1000_gbp', blocks: 1000, amount: 1000, currency: 'gbp', label: '1,000 Blocks' },
  { id: 'blocks_2500_gbp', blocks: 2500, amount: 2500, currency: 'gbp', label: '2,500 Blocks' }
]);

export async function verifyStripeAccount() {
  const acct = await stripe.accounts.retrieve();
  const name = acct.business_profile?.name || acct.company?.name || acct.settings?.dashboard?.display_name || '';
  if (config.stripeMode === 'live' && name && name.toLowerCase() !== config.expectedBusinessName.toLowerCase()) {
    throw new Error(`Stripe account business name '${name}' does not match expected '${config.expectedBusinessName}'`);
  }
  return { id: acct.id, livemode: config.stripeMode === 'live', businessName: name || config.expectedBusinessName };
}

export async function createTopUp(user, packageId, requestKey) {
  const pack = packages.find(p => p.id === packageId);
  if (!pack) throw Object.assign(new Error('Unknown Blocks package'), { status: 400 });
  if (!requestKey || requestKey.length < 12) throw Object.assign(new Error('Idempotency-Key is required'), { status: 400 });

  const existing = await pool.query(`SELECT id,stripe_payment_intent_id,status FROM stripe_topups WHERE user_id=$1 AND request_key=$2`, [user.id, requestKey]);
  if (existing.rowCount) {
    const topup = existing.rows[0];
    const pi = await stripe.paymentIntents.retrieve(topup.stripe_payment_intent_id);
    return { topupId: topup.id, clientSecret: pi.client_secret, publishableKey: config.stripePublishableKey, status: topup.status };
  }

  const topupId = crypto.randomUUID();
  const customer = await ensureStripeCustomer(user);
  const pi = await stripe.paymentIntents.create({
    amount: pack.amount,
    currency: pack.currency,
    customer,
    automatic_payment_methods: { enabled: true },
    description: `${pack.label} for Pride`,
    metadata: {
      pride_topup_id: topupId,
      pride_user_id: user.id,
      blocks_amount: String(pack.blocks),
      merchant_legal_name: config.expectedBusinessName
    }
  }, { idempotencyKey: `pride-topup:${user.id}:${requestKey}` });

  await pool.query(
    `INSERT INTO stripe_topups (id,user_id,package_id,blocks_amount,fiat_amount,currency,stripe_payment_intent_id,request_key,status)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'pending')`,
    [topupId,user.id,pack.id,pack.blocks,pack.amount,pack.currency,pi.id,requestKey]
  );
  return { topupId, clientSecret: pi.client_secret, publishableKey: config.stripePublishableKey, status: 'pending' };
}

async function ensureStripeCustomer(user) {
  const r = await pool.query(`SELECT stripe_customer_id FROM users WHERE id=$1`, [user.id]);
  if (r.rows[0]?.stripe_customer_id) return r.rows[0].stripe_customer_id;
  const customer = await stripe.customers.create({ email: user.email, name: user.display_name, metadata: { pride_user_id: user.id, username: user.username } }, { idempotencyKey: `pride-customer:${user.id}` });
  await pool.query(`UPDATE users SET stripe_customer_id=$1 WHERE id=$2 AND stripe_customer_id IS NULL`, [customer.id,user.id]);
  return customer.id;
}

export async function topUpStatus(userId, topupId) {
  const r = await pool.query(`SELECT id,blocks_amount,fiat_amount,currency,status,created_at,completed_at FROM stripe_topups WHERE id=$1 AND user_id=$2`, [topupId,userId]);
  if (!r.rowCount) throw Object.assign(new Error('Top-up not found'), { status: 404 });
  return { ...r.rows[0], blocks_amount:Number(r.rows[0].blocks_amount), fiat_amount:Number(r.rows[0].fiat_amount) };
}

export async function handleStripeWebhook(rawBody, signature) {
  const event = stripe.webhooks.constructEvent(rawBody, signature, config.stripeWebhookSecret);

  // Record receipt idempotently, then atomically claim only an unprocessed event.
  // A stale claim may be reclaimed after five minutes so a process crash cannot
  // permanently suppress Stripe's later retries.
  await pool.query(
    `INSERT INTO stripe_webhook_events (stripe_event_id,event_type)
     VALUES ($1,$2) ON CONFLICT (stripe_event_id) DO NOTHING`,
    [event.id,event.type]
  );
  const claimed = await pool.query(
    `UPDATE stripe_webhook_events
        SET processing_started_at=now(), processing_error=NULL,
            processing_attempts=processing_attempts+1
      WHERE stripe_event_id=$1
        AND processed_at IS NULL
        AND (processing_started_at IS NULL OR processing_started_at < now() - interval '5 minutes')
      RETURNING id`,
    [event.id]
  );
  if (!claimed.rowCount) {
    const state = await pool.query(
      `SELECT processed_at,processing_started_at FROM stripe_webhook_events WHERE stripe_event_id=$1`,
      [event.id]
    );
    return { duplicate: Boolean(state.rows[0]?.processed_at), inProgress: !state.rows[0]?.processed_at };
  }

  try {
    if (event.type === 'payment_intent.succeeded') await settleSuccessfulPayment(event.data.object);
    if (event.type === 'payment_intent.payment_failed' || event.type === 'payment_intent.canceled') {
      await pool.query(`UPDATE stripe_topups SET status=$2, updated_at=now() WHERE stripe_payment_intent_id=$1 AND status='pending'`, [event.data.object.id, event.type === 'payment_intent.canceled' ? 'canceled' : 'failed']);
    }
    if (event.type === 'charge.dispute.created') await freezeForCharge(event.data.object, 'stripe_dispute');
    if (event.type === 'charge.refunded') await handleRefundedCharge(event.data.object);
    await pool.query(
      `UPDATE stripe_webhook_events
          SET processed_at=now(), processing_started_at=NULL, processing_error=NULL
        WHERE stripe_event_id=$1`,
      [event.id]
    );
    return { duplicate: false, inProgress: false };
  } catch (error) {
    await pool.query(
      `UPDATE stripe_webhook_events
          SET processing_started_at=NULL, processing_error=$2
        WHERE stripe_event_id=$1`,
      [event.id, String(error.message || error).slice(0,1000)]
    );
    throw error;
  }
}

async function settleSuccessfulPayment(pi) {
  await tx(async client => {
    const r = await client.query(`SELECT * FROM stripe_topups WHERE stripe_payment_intent_id=$1 FOR UPDATE`, [pi.id]);
    if (!r.rowCount) throw new Error(`Unknown PaymentIntent ${pi.id}`);
    const t = r.rows[0];
    if (t.status === 'succeeded') return;
    if (Number(pi.amount_received) !== Number(t.fiat_amount) || pi.currency !== t.currency) throw new Error(`PaymentIntent amount/currency mismatch for ${pi.id}`);
    const metaBlocks = Number(pi.metadata?.blocks_amount || 0);
    if (metaBlocks !== Number(t.blocks_amount) || pi.metadata?.pride_user_id !== t.user_id) throw new Error(`PaymentIntent metadata mismatch for ${pi.id}`);
    await client.query(`SELECT post_topup_credit($1,$2,$3,$4)`, [t.user_id, Number(t.blocks_amount), pi.id, t.id]);
    await client.query(`UPDATE stripe_topups SET status='succeeded', completed_at=now(), updated_at=now() WHERE id=$1`, [t.id]);
  });
}

async function freezeForCharge(charge, reason) {
  const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : charge.payment_intent?.id;
  if (!piId) return;
  await pool.query(`UPDATE users SET status='frozen', updated_at=now() WHERE id=(SELECT user_id FROM stripe_topups WHERE stripe_payment_intent_id=$1)`, [piId]);
  await pool.query(`INSERT INTO account_security_events (user_id,kind,reference) SELECT user_id,$2,$1 FROM stripe_topups WHERE stripe_payment_intent_id=$1 ON CONFLICT DO NOTHING`, [piId,reason]);
}

async function handleRefundedCharge(charge) {
  const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : charge.payment_intent?.id;
  if (!piId || Number(charge.amount_refunded || 0) <= 0) return;

  // Full refunds reverse the complete Blocks top-up. Partial refunds are not
  // converted proportionally without an explicit product rule; freeze the
  // account for reconciliation so fully spendable Blocks cannot remain unnoticed.
  if (!charge.refunded) {
    await freezeForCharge(charge, 'stripe_partial_refund');
    return;
  }

  await tx(async client => {
    const r = await client.query(`SELECT * FROM stripe_topups WHERE stripe_payment_intent_id=$1 FOR UPDATE`, [piId]);
    if (!r.rowCount || r.rows[0].status === 'refunded') return;
    const t = r.rows[0];
    await client.query(`SELECT post_topup_reversal($1,$2,$3,$4)`, [t.user_id,Number(t.blocks_amount),piId,t.id]);
    await client.query(`UPDATE stripe_topups SET status='refunded', updated_at=now() WHERE id=$1`, [t.id]);
    await client.query(`UPDATE users SET status='frozen', updated_at=now() WHERE id=$1`, [t.user_id]);
  });
}
