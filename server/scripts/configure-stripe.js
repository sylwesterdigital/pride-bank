import Stripe from 'stripe';
const secret=(process.env.STRIPE_SECRET_KEY||'').trim();
const base=(process.env.PUBLIC_BASE_URL||'').trim().replace(/\/$/,'');
if (!/^sk_(test|live)_/.test(secret)) throw new Error('STRIPE_SECRET_KEY is not configured');
if (!/^https:\/\//.test(base)) throw new Error('PUBLIC_BASE_URL must be HTTPS before Stripe webhook setup');
const stripe=new Stripe(secret,{appInfo:{name:'Pride Blocks bootstrap',version:'0.3.2'}});
const url=`${base}/api/v1/stripe/webhook`;
const events=['payment_intent.succeeded','payment_intent.payment_failed','payment_intent.canceled','charge.dispute.created','charge.refunded'];
const listed=await stripe.webhookEndpoints.list({limit:100});
const existing=listed.data.find(x=>x.url===url && x.status==='enabled');
if (existing) {
  console.log(`EXISTING_WEBHOOK_ID=${existing.id}`);
  process.exit(2); // secret cannot be retrieved from an existing endpoint
}
const ep=await stripe.webhookEndpoints.create({url,enabled_events:events,description:'Pride Blocks settlement webhook'});
console.log(`STRIPE_WEBHOOK_SECRET=${ep.secret}`);
console.log(`STRIPE_WEBHOOK_ID=${ep.id}`);
