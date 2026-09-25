// Dry-run the transaction the page would hand a wallet.
//
//   npm run dry-run                       # 2,000,000 from the recorded taker
//   SENDER=0x... AMOUNT=500000 npm run dry-run
//
// Signing needs a wallet, and a wallet needs a human, so the sign-and-send path
// cannot be exercised in a test. What can be exercised is everything up to it:
// this builds the transaction with `lib/buildRoute.ts` -- the module the page
// uses, not a copy -- from a plan the running API produced against live state,
// and asks the chain to execute it without a signature.
//
// Nothing is sent and nothing changes. What comes back answers the two
// questions worth asking: does the chain accept the programmable transaction
// the page constructs, and does it pay what the Rust optimizer predicted. The
// second is the same check `scripts/route.py execute` makes after a real send.
//
// Needs `braid-server` running (BRAID_API, default http://127.0.0.1:8080).
//
// Talks gRPC: public fullnodes have retired their JSON-RPC methods.

import { SuiGrpcClient } from '@mysten/sui/grpc';
import { buildRoute } from '../lib/buildRoute.ts';
import type { Call, Plan } from '../lib/api.ts';

const API = process.env.BRAID_API ?? 'http://127.0.0.1:8080';
const AMOUNT = Number(process.env.AMOUNT ?? 2_000_000);
// The address that sent the first four-venue route. It holds testnet SUI for
// gas and is not the book's maker, so its legs are not self-trades.
const SENDER =
  process.env.SENDER ?? '0x633a98b9d9dad869d29edd98408b2fa2920b5e2dd31abc8babb4eea9d42c73ad';

const VENUES = ['cpmm', 'stable', 'clmm', 'clob'];

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(API + path, init);
  const text = await res.text();
  if (!res.ok) throw new Error(`${path}: ${text.slice(0, 300)}`);
  return (text ? JSON.parse(text) : null) as T;
}

// A plan against the committed snapshot would name a min_out the pools have
// moved away from, so read the chain first.
console.log('reading live venue state...');
await api('/api/refresh', { method: 'POST' });

const plan = await api<Plan>('/api/route', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ world: 'sui-testnet', amountIn: AMOUNT, slippageBps: 0 }),
});

if (!plan.live) throw new Error('the plan is not against live state');
const call: Call | null = plan.call;
if (!call) throw new Error('no executable plan for this order');

console.log(`plan: ${AMOUNT} in -> ${plan.totalOut} out, min_out ${plan.minOut}`);

const tx = buildRoute(call, SENDER);
const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: process.env.SUI_GRPC ?? 'https://fullnode.testnet.sui.io:443',
});

console.log('simulating...\n');
const sim = (await client.core.simulateTransaction({
  transaction: tx,
  include: { effects: true, events: true },
})) as any;

const result = sim.$kind === 'Transaction' ? sim.Transaction : sim.FailedTransaction;
const status = result?.status;
// gRPC names these `eventType` and `json`, where JSON-RPC used `type` and
// `parsedJson`.
const events = (result?.events ?? []).filter((e: any) => e.eventType?.includes('::route::'));
const legs = events.filter((e: any) => e.eventType.endsWith('LegExecuted')).map((e: any) => e.json);
const routed = events.find((e: any) => e.eventType.endsWith('Routed'))?.json;

let mismatches = 0;
const row = (a: string, b: string, c: string, d: string, e: string) =>
  a.padEnd(8) + b.padStart(12) + c.padStart(12) + d.padStart(12) + e.padStart(12);

if (legs.length) {
  console.log(row('venue', 'in (plan)', 'in (chain)', 'out (plan)', 'out (chain)'));
  call.legs.forEach((want, i) => {
    const got = legs[i];
    if (!got) return;
    const ok = want.expected_spent === got.amount_in && want.expected_out === got.amount_out;
    if (!ok) mismatches++;
    console.log(
      row(VENUES[Number(got.venue)], want.expected_spent, got.amount_in, want.expected_out, got.amount_out) +
        (ok ? '  ok' : '  MISMATCH'),
    );
  });
}

if (routed) {
  const ok = routed.amount_out === call.expected_out && routed.unspent === call.expected_unspent;
  if (!ok) mismatches++;
  console.log(row('total', '', '', call.expected_out, routed.amount_out) + (ok ? '  ok' : '  MISMATCH'));
  console.log(`unspent  plan ${call.expected_unspent}, chain ${routed.unspent}; min_out ${routed.min_out}`);
}

const ok = status?.success === true && mismatches === 0 && legs.length > 0;
console.log(
  ok
    ? '\nthe chain accepts the transaction the page builds, and pays the plan exactly'
    : '\nDRY RUN FAILED',
);
if (!status?.success) console.log('status:', JSON.stringify(status));
process.exit(ok ? 0 : 1);
