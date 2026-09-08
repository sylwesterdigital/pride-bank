const required = (name) => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
};

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 4317),
  databaseUrl: required('DATABASE_URL'),
  databaseSSL: process.env.DATABASE_SSL === 'true',
  sessionPepper: required('SESSION_PEPPER'),
  stripeSecretKey: required('STRIPE_SECRET_KEY'),
  stripePublishableKey: required('STRIPE_PUBLISHABLE_KEY'),
  stripeWebhookSecret: required('STRIPE_WEBHOOK_SECRET'),
  stripeMode: process.env.STRIPE_MODE || 'test',
  stripeAccountId: process.env.STRIPE_ACCOUNT_ID?.trim() || '',
  expectedBusinessName: process.env.STRIPE_EXPECTED_BUSINESS_NAME || 'WORKWORK.FUN LTD',
  publicBaseUrl: required('PUBLIC_BASE_URL').replace(/\/$/, ''),
  iosBlocksPurchaseRail: process.env.IOS_BLOCKS_PURCHASE_RAIL || 'stripe'
};

if (!['test', 'live'].includes(config.stripeMode)) throw new Error('STRIPE_MODE must be test or live');
if (config.stripeMode === 'live' && !config.stripeSecretKey.startsWith('sk_live_')) throw new Error('STRIPE_MODE=live requires a live Stripe secret key');
if (config.stripeMode === 'test' && !config.stripeSecretKey.startsWith('sk_test_')) throw new Error('STRIPE_MODE=test requires a test Stripe secret key');
if (config.sessionPepper.length < 32) throw new Error('SESSION_PEPPER must be at least 32 characters');
