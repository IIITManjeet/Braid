'use client';

import dynamic from 'next/dynamic';
import { useState } from 'react';

import type { Plan, World } from '@/lib/api';
import { asCliCommand } from '@/lib/buildRoute';
import { fmt } from '@/lib/format';
import { venueColor, venueLabel } from '@/lib/venues';
import { Card, Swatch, useToast } from '@/components/ui';
import { useWorld } from '@/components/WorldProvider';

// Wallet discovery is a browser handshake, and dApp Kit reads browser storage
// to remember the last wallet. Neither exists during server rendering.
const WalletSection = dynamic(() => import('./wallet/WalletSection'), {
  ssr: false,
  loading: () => (
    <div className="note">
      <span className="spinner" />
      Loading wallet support…
    </div>
  ),
});

export default function ExecutePanel({ plan, world }: { plan: Plan; world: World }) {
  if (!world.executable) {
    return (
      <Card title="Execute">
        <p className="note">
          The router test world is a fixture, not a chain — there is nothing to send a transaction
          to. Switch the venue state to <strong>Sui testnet</strong> to execute a real route.
        </p>
      </Card>
    );
  }

  const call = plan.call;
  if (!call) {
    return (
      <Card title="Execute">
        <p className="note">No executable plan for this order.</p>
      </Card>
    );
  }

  return (
    <Card
      title="Execute on Sui testnet"
      sub={
        <>
          One transaction: mint the input, open the route, one call per leg, then close it.{' '}
          <code>Route</code> has no abilities, so a transaction that opens one cannot be built
          without the <code>finish</code> that enforces <code>min_out</code> on the total.
        </>
      }
    >
      {!plan.live ? <StaleWarning /> : null}

      <WhatGetsSigned plan={plan} call={call} />
      <WalletSection plan={plan} call={call} />
      <CliFallback command={asCliCommand(call)} />
    </Card>
  );
}

function StaleWarning() {
  const { canRefresh } = useWorld();
  return (
    <div className="banner inset">
      <strong>Stale state. </strong>
      This plan was made against the committed snapshot, which is older than the pools, so its{' '}
      <code>min_out</code> will almost certainly abort.{' '}
      {canRefresh
        ? 'Use “Refresh chain” before executing.'
        : 'Reading live state needs the Sui CLI, which this deployment does not carry — run it locally with bash scripts/web.sh to execute.'}
    </div>
  );
}

function WhatGetsSigned({ plan, call }: { plan: Plan; call: NonNullable<Plan['call']> }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <h3 style={{ fontSize: 13, margin: '0 0 8px' }}>What gets signed</h3>
      <ol className="note" style={{ margin: 0, paddingLeft: 20 }}>
        <li style={{ margin: '3px 0' }}>
          mint {fmt(Number(call.amount_in))} {call.mint_symbol ?? 'input'} — the treasury cap is
          shared, testnet faucet behaviour
        </li>
        <li style={{ margin: '3px 0' }}>
          begin the route with <code>min_out</code> = {fmt(Number(call.min_out))}
        </li>
        {call.legs.map((leg, i) => (
          <li key={i} style={{ margin: '3px 0' }}>
            <Swatch color={venueColor(leg.venue)} />
            {venueLabel(leg.venue)}: {fmt(Number(leg.amount))} in, {fmt(Number(leg.expected_out))}{' '}
            expected out
          </li>
        ))}
        <li style={{ margin: '3px 0' }}>finish — the min_out check, on the total</li>
        <li style={{ margin: '3px 0' }}>transfer the bought coin and any change back to you</li>
      </ol>
      <p className="hint">
        {plan.slippageBps === 0
          ? 'Slippage is zero, so the chain has to pay the prediction exactly — a one-unit shortfall aborts the whole transaction. That is the point of the demonstration.'
          : `min_out is ${plan.slippageBps} bps below the predicted ${fmt(plan.totalOut)}.`}
      </p>
    </div>
  );
}

function CliFallback({ command }: { command: string }) {
  const toast = useToast();
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
      toast('Command copied.', 'good', 2500);
    } catch {
      toast('Could not copy — select the text instead.', 'bad');
    }
  }

  return (
    <details className="raw">
      <summary>The same route as a sui client ptb command</summary>
      <div className="row between" style={{ marginTop: 8 }}>
        <span className="hint" style={{ margin: 0 }}>
          Identical to what <code>scripts/route.py execute</code> builds.
        </span>
        <button type="button" className="btn ghost sm" onClick={copy}>
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <pre>{command}</pre>
    </details>
  );
}
