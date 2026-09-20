// The route, as a programmable transaction.
//
// Exactly what `scripts/route.py execute` builds, in the same order: mint the
// input, `begin` the route, one call per leg, `finish`, transfer both coins
// back. `Route` has no abilities, so a PTB that calls `begin` cannot be
// completed without handing it to `finish` -- which is where `min_out` is
// enforced, on the total. This file could not omit that check even if it tried.
//
// The input coin is minted in the same transaction that spends it. That works
// only because `braid_test_coins` shares its `TreasuryCap` on purpose: testnet
// faucet behaviour, documented in that package as never-for-mainnet.

import { Transaction } from '@mysten/sui/transactions';
import type { Call } from './api';

/** `0x..::tusd::TUSD` -> `0x..::tusd::mint` */
const mintTarget = (coinType: string) => `${coinType.split('::').slice(0, 2).join('::')}::mint`;

export function buildRoute(call: Call, sender: string): Transaction {
  if (!call.mint_treasury) {
    throw new Error('no test-coin treasury recorded for this deployment');
  }

  const tx = new Transaction();
  tx.setSender(sender);

  const pair: [string, string] = [call.coin_in, call.coin_out];
  const router = call.router_package;

  const input = tx.moveCall({
    target: mintTarget(call.coin_in),
    arguments: [tx.object(call.mint_treasury), tx.pure.u64(call.amount_in)],
  });

  const route = tx.moveCall({
    target: `${router}::route::begin`,
    typeArguments: pair,
    arguments: [input, tx.pure.u64(call.min_out)],
  });

  for (const leg of call.legs) {
    tx.moveCall({
      target: `${router}::route::${leg.function}`,
      typeArguments: leg.type_args,
      // Legs pass no minimum of their own: a per-leg bound would be the wrong
      // check, because the guarantee is about the total.
      arguments: [route, tx.object(leg.object), tx.pure.u64(leg.amount)],
    });
  }

  const [bought, change] = tx.moveCall({
    target: `${router}::route::finish`,
    typeArguments: pair,
    arguments: [route],
  });

  tx.transferObjects([bought, change], sender);
  return tx;
}

/**
 * The same route as a `sui client ptb` command.
 *
 * The path when no wallet is installed, and something readable to compare
 * against what the wallet is being asked to sign.
 */
export function asCliCommand(call: Call, sender = '<your-address>'): string {
  const pair = `<${call.coin_in},${call.coin_out}>`;
  const lines = [
    `sui client ptb --sender @${sender} \\`,
    `  --move-call ${mintTarget(call.coin_in)} @${call.mint_treasury} ${call.amount_in} --assign coin \\`,
    `  --move-call ${call.router_package}::route::begin "${pair}" coin ${call.min_out} --assign route \\`,
  ];
  for (const leg of call.legs) {
    lines.push(
      `  --move-call ${call.router_package}::route::${leg.function} ` +
        `"<${leg.type_args[0]},${leg.type_args[1]}>" route @${leg.object} ${leg.amount} \\`,
    );
  }
  lines.push(
    `  --move-call ${call.router_package}::route::finish "${pair}" route --assign done \\`,
    `  --transfer-objects "[done.0, done.1]" @${sender}`,
  );
  return lines.join('\n');
}
