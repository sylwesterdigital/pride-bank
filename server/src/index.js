import express from 'express';
import helmet from 'helmet';
import { config } from './config.js';
import { pool } from './db.js';
import { register, login, requireAuth, logout } from './auth.js';
import { balanceFor, activityFor, transferBlocks } from './ledger.js';
import { packages, createTopUp, topUpStatus, handleStripeWebhook, verifyStripeAccount } from './stripe.js';

const releaseVersion = process.env.PRIDE_RELEASE_VERSION || '0.3.8';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));

app.post('/v1/stripe/webhook', express.raw({ type: 'application/json', limit: '1mb' }), async (req,res,next) => {
  try {
    const signature = req.get('stripe-signature');
    if (!signature) return res.status(400).send('missing signature');
    await handleStripeWebhook(req.body, signature);
    res.sendStatus(200);
  } catch (error) {
    if (error?.type === 'StripeSignatureVerificationError') return res.status(400).send('invalid signature');
    next(error);
  }
});

app.use(express.json({ limit: '128kb' }));

app.get('/healthz', async (_req,res,next) => {
  try { await pool.query('SELECT 1'); res.json({ ok:true, version:releaseVersion, payments:config.stripeMode }); } catch(e) { next(e); }
});
app.get('/v1/config', (_req,res) => res.json({ iosBlocksPurchaseRail: config.iosBlocksPurchaseRail, merchant: config.expectedBusinessName }));
app.post('/v1/auth/register', async (req,res,next) => { try { res.status(201).json(await register(req.body || {})); } catch(e) { next(e); } });
app.post('/v1/auth/login', async (req,res,next) => { try { res.json(await login(req.body || {})); } catch(e) { next(e); } });
app.post('/v1/auth/logout', requireAuth, async (req,res,next) => { try { await logout(req.sessionTokenHash); res.sendStatus(204); } catch(e) { next(e); } });
app.get('/v1/me', requireAuth, async (req,res,next) => { try { res.json({ user:req.user, blocksBalance:await balanceFor(req.user.id) }); } catch(e) { next(e); } });
app.get('/v1/blocks/activity', requireAuth, async (req,res,next) => { try { res.json({ items:await activityFor(req.user.id,req.query.limit) }); } catch(e) { next(e); } });
app.post('/v1/blocks/transfers', requireAuth, async (req,res,next) => { try { res.status(201).json(await transferBlocks({ fromUserId:req.user.id, toUsername:req.body?.toUsername, amount:req.body?.amount, note:req.body?.note, idempotencyKey:req.get('idempotency-key') })); } catch(e) { next(e); } });
app.get('/v1/blocks/packages', requireAuth, (_req,res) => res.json({ currency:'gbp', merchant:config.expectedBusinessName, packages }));
app.post('/v1/blocks/topups/payment-intent', requireAuth, async (req,res,next) => { try { res.status(201).json(await createTopUp(req.user,req.body?.packageId,req.get('idempotency-key'))); } catch(e) { next(e); } });
app.get('/v1/blocks/topups/:id', requireAuth, async (req,res,next) => { try { res.json(await topUpStatus(req.user.id,req.params.id)); } catch(e) { next(e); } });

app.use((error, _req, res, _next) => {
  console.error(error);
  const status = Number(error.status) || 500;
  res.status(status).json({ error: status >= 500 ? 'server_error' : 'request_error', message: status >= 500 ? 'Request could not be completed' : error.message });
});

const server = app.listen(config.port, '127.0.0.1', async () => {
  try {
    const stripeAccount = await verifyStripeAccount();
    console.log(`Pride Blocks API v${releaseVersion} listening on 127.0.0.1:${config.port}; Stripe ${stripeAccount.id}; ${config.stripeMode}`);
  } catch (error) {
    console.error('Startup safety check failed:', error);
    server.close(() => process.exit(1));
  }
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
