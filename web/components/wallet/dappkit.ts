// The dApp Kit instance.
//
// Created at module scope, which is safe because this module is only ever
// reached through a `ssr: false` dynamic import -- it touches browser storage
// to remember the last connected wallet, and that does not exist on the server.
//
// Testnet only: the Braid packages are published there and nowhere else, and
// offering a network picker that cannot work would be a lie in the UI.

import { createDAppKit } from '@mysten/dapp-kit-core';
import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc';

export const dAppKit = createDAppKit({
  networks: ['testnet'],
  defaultNetwork: 'testnet',
  createClient: (network) =>
    new SuiJsonRpcClient({ url: getJsonRpcFullnodeUrl(network), network }),

  // The hosted Slush web wallet is off because its metadata endpoint serves no
  // CORS headers, so enabling it means three failed requests and a console
  // error on every page load. This does not affect wallet extensions: those
  // register themselves through the Wallet Standard, Slush's included.
  slushWalletConfig: null,
});
