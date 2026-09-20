// The typed surface of `braid-server`.
//
// The server wraps `braid-quote` and `braid-route`, the Rust crates the
// differential fuzzer checks against both Move VMs. Nothing here recomputes a
// price: a number in this file came off the same code path the generated Move
// tests hold the chain to.

export type VenueKind = 'cpmm' | 'stable' | 'clmm' | 'clob';

export type TickState = {
  tick: number;
  liquidityGross: string;
  liquidityNet: string;
};

/** Discriminated on `kind`: each venue exposes the state it prices from. */
export type Venue = {
  kind: VenueKind;
  object: string;
  forward: boolean;
  label: string;
  blurb: string;
} & Partial<{
  // cpmm / stable
  reserveIn: number;
  reserveOut: number;
  feeBps: number;
  invariant: number;
  amp: number;
  // clmm
  sqrtPrice: string;
  tick: number;
  liquidity: string;
  tickSpacing: number;
  zeroForOne: boolean;
  ticks: TickState[];
  // clob
  tickSize: number;
  lotSize: number;
  takerFeeBps: number;
  buyBase: boolean;
  asks: [number, number][];
  bids: [number, number][];
}>;

export type World = {
  id: string;
  label: string;
  description: string;
  /** Whether the venues are real Sui objects a wallet could trade through. */
  executable: boolean;
  /** Whether the state was read from the chain during this server's life. */
  live: boolean;
  source: string;
  routerPackage: string;
  coinIn: string;
  coinOut: string;
  venues: Venue[];
};

export type Leg = {
  index: number;
  venue: VenueKind;
  /** What the route hands the venue. */
  amount: number;
  /** What the venue consumes of it; the rest comes back. */
  spent: number;
  out: number;
  share: number;
  effectivePrice: number;
  /** Output for one more unit here, per unit consumed. Null when it cannot take more. */
  marginal: number | null;
};

export type CallLeg = {
  venue: VenueKind;
  object: string;
  function: string;
  type_args: [string, string];
  amount: string;
  expected_spent: string;
  expected_out: string;
};

/** The exact Move calls, when there is a chain to send them to. */
export type Call = {
  router_package: string;
  coin_in: string;
  coin_out: string;
  amount_in: string;
  expected_out: string;
  expected_unspent: string;
  slippage_bps: number;
  min_out: string;
  legs: CallLeg[];
  mint_treasury?: string;
  mint_symbol?: string;
};

export type Plan = {
  world: string;
  executable: boolean;
  live: boolean;
  amountIn: number;
  slippageBps: number;
  totalOut: number;
  unspent: number;
  minOut: number;
  legs: Leg[];
  idleVenues: { index: number; venue: VenueKind; marginal: number | null }[];
  allIn: { index: number; venue: VenueKind; out: number; spent: number; fillsWholeOrder: boolean }[];
  bestSingle: { index: number; venue: VenueKind; out: number } | null;
  bestFillingWholeOrder: { index: number; venue: VenueKind; out: number; gain: number; gainPct: number } | null;
  call: Call | null;
};

export type CurvePoint = { in: number; out: number; spent: number };
export type Curves = {
  world: string;
  sizes: number[];
  venues: { venue: VenueKind; index: number; points: CurvePoint[] }[];
  route: CurvePoint[] | null;
};

export type GasRow = {
  route: string;
  legs: number[];
  net?: number;
  computationCost?: number;
  storageCost?: number;
  storageRebate?: number;
  gasUnits?: number;
  gasUnitPrice?: number;
  tx?: string;
};
export type GasResult = { chain: string; network: string; amount: number; rows: GasRow[] } | null;
export type Bench = { sui: GasResult; aptos: GasResult; latency: string | null };

export type Corpus = { path: string; cases: number; asserts: number; tests: number; bytes: number } | null;
export type Suite = {
  venue: string;
  package: string;
  kind: 'formula' | 'scenario' | 'plan';
  sui: Corpus;
  aptos: Corpus;
  identical: boolean;
};
export type Difftest = {
  suites: Suite[];
  formulaCases: number;
  scenarios: number;
  plans: number;
  totalAsserts: number;
};

export type Deployments = {
  sui: { testnet: any; firstRoutePlan: any; firstRouteSnapshot: any };
  aptos: { local: any; testnet: any };
  explorers: { suiTx: string; suiObject: string; aptosTx: string; aptosAccount: string };
};

// ---------------------------------------------------------------- client -- //

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init);
  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    /* a non-JSON error body is reported as-is below */
  }
  if (!res.ok) throw new Error(data?.error || text || `${res.status} ${res.statusText}`);
  return data as T;
}

const post = <T,>(path: string, body: unknown) =>
  req<T>(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

export const getWorlds = () => req<{ worlds: World[] }>('/api/worlds').then((r) => r.worlds);

export const getRoute = (world: string, amountIn: number, slippageBps: number) =>
  post<Plan>('/api/route', { world, amountIn, slippageBps });

export const getCurves = (world: string, max = 16_000_000, points = 44) =>
  req<Curves>(`/api/curve?world=${encodeURIComponent(world)}&max=${max}&points=${points}&route=true`);

export const getBench = () => req<Bench>('/api/bench');
export const getDifftest = () => req<Difftest>('/api/difftest');
export const getDeployments = () => req<Deployments>('/api/deployments');

/** Re-read live Sui venue state. The only call that touches the network. */
export const refreshChain = () => post<World>('/api/refresh', {});
