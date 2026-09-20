'use client';

import { getBench, type GasResult } from '@/lib/api';
import { compact, fmt } from '@/lib/format';
import { useAsync } from '@/lib/useAsync';
import { venueColor, venueLabel } from '@/lib/venues';
import { Card, Empty, Loading, Raw, Swatch, Table } from '@/components/ui';
import BarsH from '@/components/charts/BarsH';

/** The row that carries only the fixed cost of a transaction with no legs. */
const EMPTY_ROUTE = 'empty route';

export default function BenchmarksPage() {
  const { data, error, loading } = useAsync(getBench, []);
  if (loading) return <Loading>Loading benchmarks</Loading>;
  if (error || !data) return <Empty>{error ?? 'No benchmark results.'}</Empty>;

  return (
    <>
      <Card
        title="Gas per venue"
        sub="The two chains rank the venues differently, and the reason is what each one charges for. On Sui a swap’s cost is almost entirely storage — computation never leaves the smallest bucket — so the order book, which rewrites the most objects, is the priciest venue. On Aptos the concentrated pool’s tick walk is."
      >
        <GasChart
          title="Sui testnet"
          data={data.sui}
          field="net"
          unit="MIST (net of storage rebate)"
        />
        <GasChart title="Aptos localnet" data={data.aptos} field="gasUnits" unit="gas units" />
      </Card>

      <Latency markdown={data.latency} />

      {data.sui || data.aptos ? (
        <Card title="Raw">
          {data.sui ? <Raw label="bench/results/gas-sui-testnet.json" value={data.sui} /> : null}
          {data.aptos ? <Raw label="bench/results/gas-aptos-local.json" value={data.aptos} /> : null}
        </Card>
      ) : null}
    </>
  );
}

/**
 * One chart per chain, never one chart with two scales: MIST and Aptos gas
 * units are different measures, and a shared axis would invite a comparison
 * that means nothing.
 */
function GasChart({
  title,
  data,
  field,
  unit,
}: {
  title: string;
  data: GasResult;
  field: 'net' | 'gasUnits';
  unit: string;
}) {
  const baseline = Number(data?.rows?.find((r) => r.route === EMPTY_ROUTE)?.[field] ?? 0);

  if (!data?.rows?.length) {
    return (
      <div className="card tight">
        <h2 style={{ fontSize: 14, margin: '0 0 2px' }}>{title}</h2>
        <Empty>No results recorded.</Empty>
      </div>
    );
  }

  return (
    <div className="card tight" style={{ marginBottom: 14 }}>
      <h2 style={{ fontSize: 14, margin: '0 0 2px' }}>{title}</h2>
      <p className="hint" style={{ margin: '0 0 12px' }}>
        {unit} · {fmt(data.amount)} in · {data.network}
      </p>

      {/* What a leg costs, not what a transaction costs.
          Every row carries the same fixed overhead -- on Sui that is most of
          the number -- so plotting the totals puts six bars of near-identical
          length on screen and hides the thing the numbers are about. Bars stay
          anchored at zero; the quantity is the difference from an empty route,
          which is the venue's own cost. The totals are in the table below. */}
      <BarsH
        rows={data.rows
          .filter((r) => r.route !== EMPTY_ROUTE)
          .map((r) => ({
            label: r.route,
            value: Math.max(0, Number(r[field] ?? 0) - baseline),
            color: venueColor(r.route),
            note: r.legs ? `legs [${r.legs.join(', ')}]` : undefined,
          }))}
        unit={`${unit}, over an empty route`}
        valueFormat={compact}
      />
      <p className="hint" style={{ margin: '2px 0 10px' }}>
        Bars show each route&rsquo;s cost <em>over an empty route</em> ({compact(baseline)} {unit}),
        which is the part the venue is responsible for. Totals are in the table.
      </p>

      <Table
        rowKey={(r) => r.route}
        columns={[
          { head: 'Route', render: (r) => r.route },
          { head: unit, num: true, render: (r) => fmt(Number(r[field] ?? 0)) },
          ...(field === 'net'
            ? [
                { head: 'Computation', num: true, render: (r: any) => fmt(r.computationCost) },
                { head: 'Storage', num: true, render: (r: any) => fmt(r.storageCost) },
                { head: 'Rebate', num: true, render: (r: any) => fmt(r.storageRebate) },
              ]
            : [{ head: 'Unit price', num: true, render: (r: any) => fmt(r.gasUnitPrice) }]),
        ]}
        rows={data.rows}
      />
    </div>
  );
}

/**
 * The latency file is a short markdown document of pipe tables. Rendering it as
 * tables beats showing it as a code block, and parsing it here keeps `bench/`
 * the single source rather than copying its numbers into the page.
 */
function Latency({ markdown }: { markdown: string | null }) {
  if (!markdown) {
    return (
      <Card title="Quote latency">
        <Empty>bench/results/latency.md not found.</Empty>
      </Card>
    );
  }

  type Block =
    | { type: 'table'; head: string[]; body: string[][] }
    | { type: 'heading'; text: string }
    | { type: 'text'; text: string };

  const blocks: Block[] = [];
  let pending: string[] = [];

  const cells = (line: string) =>
    line
      .split('|')
      .slice(1, -1)
      .map((c) => c.trim());

  const flush = () => {
    if (pending.length >= 2) {
      const head = cells(pending[0]);
      const body = pending
        .slice(2)
        .map(cells)
        .filter((r) => r.length === head.length);
      blocks.push({ type: 'table', head, body });
    }
    pending = [];
  };

  for (const line of markdown.split(/\r?\n/)) {
    if (line.trim().startsWith('|')) {
      pending.push(line);
      continue;
    }
    flush();
    const t = line.trim();
    if (!t) continue;
    blocks.push(t.startsWith('###') ? { type: 'heading', text: t.replace(/^#+\s*/, '') } : { type: 'text', text: t });
  }
  flush();

  return (
    <Card title="Quote and planning latency">
      {blocks.map((b, i) => {
        if (b.type === 'heading') {
          return (
            <h3 key={i} style={{ fontSize: 13, margin: '18px 0 8px' }}>
              {b.text}
            </h3>
          );
        }
        if (b.type === 'text') {
          return (
            <p key={i} className="hint" style={{ margin: '0 0 6px' }}>
              {b.text}
            </p>
          );
        }
        return (
          <div className="table-wrap" key={i}>
            <table>
              <thead>
                <tr>
                  {b.head.map((c, j) => (
                    <th key={j} className={j ? 'num' : ''}>
                      {c}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {b.body.map((r, j) => (
                  <tr key={j}>
                    {r.map((c, k) =>
                      k ? (
                        <td key={k} className="num">
                          {c}
                        </td>
                      ) : (
                        <td key={k}>
                          {venueLabel(c) !== c ? <Swatch color={venueColor(c)} /> : null}
                          {c === 'optimize' ? <strong>{c}</strong> : c}
                        </td>
                      ),
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      })}
      <p className="hint">
        A single quote is microseconds; planning a four-way split is milliseconds, because the
        optimizer quotes hundreds of times — once per chunk in the fill, then again for every
        candidate transfer as the step halves down to one unit.
      </p>
    </Card>
  );
}
