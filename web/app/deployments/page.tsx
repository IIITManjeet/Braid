'use client';

import { getDeployments, type Deployments } from '@/lib/api';
import { fmt, shortAddr } from '@/lib/format';
import { useAsync } from '@/lib/useAsync';
import { Card, Empty, ExternalLink, KV, Loading, Pill, Raw, Stat, Table } from '@/components/ui';

export default function DeploymentsPage() {
  const { data, error, loading } = useAsync(getDeployments, []);
  if (loading) return <Loading>Loading deployment records</Loading>;
  if (error || !data) return <Empty>{error ?? 'No deployment records.'}</Empty>;

  return (
    <>
      <SuiSection d={data} />
      <AptosSection d={data} />
    </>
  );
}

// ------------------------------------------------------------------- sui -- //

function SuiSection({ d }: { d: Deployments }) {
  const t = d.sui?.testnet;
  const ex = d.explorers;
  if (!t) {
    return (
      <Card title="Sui testnet">
        <Empty>deployments/testnet.json not found.</Empty>
      </Card>
    );
  }

  const packages = Object.entries(t)
    .filter(([k, v]: [string, any]) => k.startsWith('braid_') && v?.packageId)
    .map(([name, v]: [string, any]) => ({ name, id: v.packageId as string }));

  const route = t.firstRoute;
  const pools: [string, any][] = Object.entries(t.pools ?? {});

  return (
    <>
      <Card
        title="Sui testnet"
        sub="Every venue package is published, and each has been exercised end to end with real trades. Sui publishes one package per transaction, so braid_math goes first and the rest import it as an on-chain dependency."
      >
        <Table
          rowKey={(r) => r.name}
          columns={[
            { head: 'Package', render: (r) => <code>{r.name}</code> },
            {
              head: 'Address',
              render: (r) => (
                <ExternalLink href={ex.suiObject + r.id}>{shortAddr(r.id, 8)}</ExternalLink>
              ),
            },
          ]}
          rows={packages}
        />
        {t._deployer ? (
          <p className="hint">
            Deployer <code>{shortAddr(t._deployer, 8)}</code>
          </p>
        ) : null}
        {t._note ? <p className="hint">{t._note}</p> : null}
      </Card>

      {route ? (
        <Card
          title="One order, four venues, one transaction"
          sub={`${fmt(route.amountIn)} ${route.coinIn} routed across all four venues with min_out set to exactly the planned output. Every leg’s on-chain event matched the Rust plan to the unit.`}
        >
          <div className="grid four">
            <Stat label="In" value={fmt(route.amountIn)} note={route.coinIn} small />
            <Stat label="Out" value={fmt(route.amountOut)} note={route.coinOut} small />
            <Stat label="min_out" value={fmt(route.minOut)} note="the prediction, exactly" small />
            <Stat
              label="vs best venue"
              value={
                route.bestVenueFillingWholeOrder
                  ? `+${((route.amountOut / route.bestVenueFillingWholeOrder.out - 1) * 100).toFixed(1)}%`
                  : '—'
              }
              note={
                route.bestVenueFillingWholeOrder
                  ? `${route.bestVenueFillingWholeOrder.venue} alone pays ${fmt(route.bestVenueFillingWholeOrder.out)}`
                  : undefined
              }
              small
              good
            />
          </div>
          <div style={{ height: 14 }} />
          <Table
            rowKey={(r) => r.venue}
            columns={[
              { head: 'Venue', render: (r) => <code>{r.venue}</code> },
              { head: 'In', num: true, render: (r) => fmt(r.in) },
              { head: 'Out', num: true, render: (r) => fmt(r.out) },
            ]}
            rows={Object.entries(route.legs ?? {}).map(([venue, v]: [string, any]) => ({
              venue,
              ...v,
            }))}
          />
          <p className="hint">
            Transaction <ExternalLink href={ex.suiTx + route.digest}>{route.digest}</ExternalLink>
          </p>
          {route.note ? <p className="hint">{route.note}</p> : null}
        </Card>
      ) : null}

      {pools.length ? (
        <Card title="Live pools" sub="Each one seeded, then traded through.">
          {pools.map(([name, p]) => (
            <Pool key={name} name={name} pool={p} suiObject={ex.suiObject} suiTx={ex.suiTx} />
          ))}
        </Card>
      ) : null}

      <Card title="Raw">
        <Raw label="deployments/testnet.json" value={t} />
      </Card>
    </>
  );
}

function Pool({
  name,
  pool,
  suiObject,
  suiTx,
}: {
  name: string;
  pool: any;
  suiObject: string;
  suiTx: string;
}) {
  const id = pool.poolId ?? pool.marketId;
  const scalars = Object.entries(pool).filter(
    ([k, v]) => typeof v !== 'object' && !k.startsWith('_'),
  ) as [string, any][];

  const swaps: [string, any][] = [];
  if (pool.firstSwap) swaps.push(['firstSwap', pool.firstSwap]);
  if (pool.firstSwaps) {
    for (const [k, v] of Object.entries(pool.firstSwaps)) {
      if (v && typeof v === 'object') swaps.push([k, v]);
    }
  }

  return (
    <div style={{ borderTop: '1px solid var(--line-soft)', paddingTop: 14, marginTop: 14 }}>
      <div className="row between">
        <h3 style={{ margin: 0, fontSize: 14 }}>
          <code>{name}</code>
        </h3>
        {id ? <ExternalLink href={suiObject + id}>{shortAddr(id, 8)}</ExternalLink> : null}
      </div>
      <div style={{ height: 8 }} />
      <KV pairs={scalars.map(([k, v]) => [k, String(v)])} />
      {swaps.map(([label, s]) => {
        const digest = s.digest ?? pool.firstSwaps?.digest;
        return (
          <div key={label} style={{ marginTop: 10 }}>
            <div className="hint" style={{ margin: '0 0 4px' }}>
              <strong>{label}</strong>
              {digest ? (
                <>
                  {' — '}
                  <ExternalLink href={suiTx + digest}>{digest}</ExternalLink>
                </>
              ) : null}
            </div>
            <KV
              pairs={Object.entries(s)
                .filter(([k, v]) => typeof v !== 'object' && k !== 'digest')
                .map(([k, v]) => [k, String(v)])}
            />
          </div>
        );
      })}
    </div>
  );
}

// ----------------------------------------------------------------- aptos -- //

function AptosSection({ d }: { d: Deployments }) {
  const ex = d.explorers;
  const entries: [string, any][] = [
    ['testnet', d.aptos?.testnet],
    ['localnet', d.aptos?.local],
  ];

  return (
    <>
      <Card
        title="Aptos"
        sub="The same packages on the other Move chain, seven of them with the test coins. Aptos keys a module by (address, name), and three packages declare a module called `pool` — so each package gets its own resource account, derived from the publisher."
      >
        {d.aptos?.testnet ? (
          <p className="note">
            <Pill kind="good">testnet deployed</Pill> Records below.
          </p>
        ) : (
          <p className="note">
            <Pill kind="warn">testnet pending</Pill> The testnet run is the project’s last open
            item — it needs APT from the browser-gated faucet before{' '}
            <code>python scripts/aptos.py all</code> can be run.
          </p>
        )}
      </Card>

      {entries.map(([label, dep]) =>
        dep ? <AptosDeployment key={label} label={label} dep={dep} ex={ex} /> : null,
      )}
    </>
  );
}

function AptosDeployment({
  label,
  dep,
  ex,
}: {
  label: string;
  dep: any;
  ex: Deployments['explorers'];
}) {
  const packages = Object.entries(dep.packages ?? {}).map(([name, v]: [string, any]) => ({
    name,
    ...v,
  }));
  const routes: any[] = dep.routes ?? [];

  return (
    <Card title={`Aptos ${label}`}>
      <KV
        pairs={[
          ['Publisher', dep._publisher ? shortAddr(dep._publisher, 8) : null],
          ['Trader', dep._trader ? shortAddr(dep._trader, 8) : null],
        ]}
      />
      <div style={{ height: 10 }} />
      <Table
        rowKey={(r) => r.name}
        columns={[
          { head: 'Package', render: (r) => <code>{r.name}</code> },
          {
            head: 'Resource account',
            render: (r) =>
              label === 'testnet' ? (
                <ExternalLink href={ex.aptosAccount + r.address + ex.aptosSuffix}>
                  {shortAddr(r.address, 8)}
                </ExternalLink>
              ) : (
                shortAddr(r.address, 8)
              ),
          },
          { head: 'Gas', num: true, render: (r) => (r.gasUsed ? fmt(r.gasUsed) : '—') },
        ]}
        rows={packages}
      />

      {routes.map((r, i) => (
        <div key={i} style={{ marginTop: 14 }}>
          <h3 style={{ fontSize: 13, margin: '0 0 8px' }}>
            Route: {fmt(r.amountIn)} in → {fmt(r.amountOut)} out
          </h3>
          <Table
            rowKey={(x) => x.venue}
            columns={[
              { head: 'Venue', render: (x) => <code>{x.venue}</code> },
              { head: 'In', num: true, render: (x) => fmt(x.in) },
              { head: 'Out', num: true, render: (x) => fmt(x.out) },
            ]}
            rows={Object.entries(r.legs ?? {}).map(([venue, v]: [string, any]) => ({ venue, ...v }))}
          />
          <p className="hint">
            {r.matchesPlan ? (
              <Pill kind="good">every leg matched the offline plan</Pill>
            ) : (
              <Pill kind="bad">differs from plan</Pill>
            )}{' '}
            min_out <code>{fmt(r.minOut)}</code> · unspent <code>{fmt(r.unspent)}</code>
            {label === 'testnet' && r.tx ? (
              <>
                {' · '}
                <ExternalLink href={ex.aptosTx + r.tx + ex.aptosSuffix}>
                  {shortAddr(r.tx, 8)}
                </ExternalLink>
              </>
            ) : null}
          </p>
        </div>
      ))}

      <Raw label={`deployments/aptos-${label}.json`} value={dep} />
    </Card>
  );
}
