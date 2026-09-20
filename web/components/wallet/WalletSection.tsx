'use client';

import { useState } from 'react';
import { DAppKitProvider, useWalletConnection } from '@mysten/dapp-kit-react';
import { ConnectButton } from '@mysten/dapp-kit-react/ui';

import { dAppKit } from './dappkit';
import { buildRoute } from '@/lib/buildRoute';
import type { Call, Plan } from '@/lib/api';
import { ExternalLink, Pill, useToast } from '@/components/ui';
import { shortAddr } from '@/lib/format';

/**
 * Connect a wallet and send the planned route.
 *
 * Loaded only in the browser (see ExecutePanel): dApp Kit discovers wallets
 * through the Wallet Standard handshake, which needs a real window.
 */
export default function WalletSection({ plan, call }: { plan: Plan; call: Call }) {
  return (
    <DAppKitProvider dAppKit={dAppKit}>
      <Inner plan={plan} call={call} />
    </DAppKitProvider>
  );
}

function Inner({ plan, call }: { plan: Plan; call: Call }) {
  const connection = useWalletConnection();
  const toast = useToast();
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState<{ digest: string; ok: boolean; error: string | null } | null>(null);

  const account = connection.isConnected ? connection.account : null;

  async function send() {
    if (!account) return;
    setSending(true);
    setSent(null);
    try {
      const transaction = buildRoute(call, account.address);
      const result = await dAppKit.signAndExecuteTransaction({ transaction });

      // The result is tagged: a transaction the chain rejected still comes back
      // with a digest. A min_out that was not met lands here rather than
      // throwing, and saying so is the whole point of the demonstration.
      const tx = result.$kind === 'Transaction' ? result.Transaction : result.FailedTransaction;
      const ok = result.$kind === 'Transaction' && tx.status.success;
      const error = tx.status.success ? null : String(tx.status.error?.message ?? 'aborted');

      setSent({ digest: tx.digest, ok, error });
      if (ok) toast('Route executed. Every leg paid what the plan predicted.', 'good');
      else toast(`The chain rejected it: ${error}`, 'bad', 10_000);
    } catch (e) {
      toast(`Not sent: ${e instanceof Error ? e.message : String(e)}`, 'bad', 10_000);
    } finally {
      setSending(false);
    }
  }

  return (
    <div>
      <div className="row" style={{ gap: 10, alignItems: 'center' }}>
        <ConnectButton />
        <button
          type="button"
          className="btn primary"
          disabled={!account || sending || !plan.live}
          onClick={send}
        >
          {sending ? 'Waiting for the wallet…' : 'Sign and send'}
        </button>
      </div>

      <div className="note" style={{ marginTop: 10 }}>
        {account ? (
          <>
            Connected <Pill kind="good">{shortAddr(account.address, 8)}</Pill> — this address needs
            testnet SUI for gas, and must not be the one that owns the book’s resting asks: the book
            refuses a self-trade.
          </>
        ) : (
          <>Connect a Sui wallet on testnet to send this route.</>
        )}
      </div>

      {!plan.live && account ? (
        <div className="note" style={{ marginTop: 6 }}>
          Sending is disabled until the venue state is refreshed — a plan built on the stale
          snapshot would name a <code>min_out</code> the pools have moved away from.
        </div>
      ) : null}

      {sent ? (
        <div className="note" style={{ marginTop: 10 }}>
          <Pill kind={sent.ok ? 'good' : 'bad'}>{sent.ok ? 'executed' : 'rejected'}</Pill>{' '}
          <ExternalLink href={`https://suiscan.xyz/testnet/tx/${sent.digest}`}>
            {sent.digest}
          </ExternalLink>
          {sent.error ? (
            <div style={{ marginTop: 4 }}>
              {sent.error} — a route that cannot pay its <code>min_out</code> aborts whole rather
              than settling for less.
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
