'use client';

import { useMemo, useState } from 'react';

import { getCurves, getRoute, type Curves, type Plan } from '@/lib/api';
import { compact, fmt, pct } from '@/lib/format';
import { useAsync } from '@/lib/useAsync';
import { venueColor, venueLabel } from '@/lib/venues';
import { useWorld } from '@/components/WorldProvider';
import { Card, Empty, Loading, Pill, Stat, Swatch, Table, useToast } from '@/components/ui';
import LineChart, { Legend, type Series } from '@/components/charts/LineChart';
import SplitBar from '@/components/SplitBar';
import ExecutePanel from '@/components/ExecutePanel';

const PRESETS = [10_000, 100_000, 1_000_000, 6_000_000, 8_000_000, 16_000_000];

export default function RoutePage() {
  const { world, worldId, loading: worldsLoading, error: worldsError } = useWorld();
  const [amountIn, setAmountIn] = useState(8_000_000);
  const [slippageBps, setSlippageBps] = useState(0);
  const [hidden, setHidden] = useState<Set<string>>(new Set());
  const [curveMode, setCurveMode] = useState<CurveMode>('price');

  const plan = useAsync<Plan | null>(
    async () => (world ? getRoute(world.id, amountIn, slippageBps) : null),
    [worldId, amountIn, slippageBps, Boolean(world)],
  );
  const curves = useAsync<Curves | null>(
    async () => (world ? getCurves(world.id) : null),
    [worldId, Boolean(world)],
  );

  if (worldsError) {
    return (
      <Card title="Cannot reach braid-server">
        <p className="sub">{worldsError}</p>
        <p className="note">
          Start it with <code>bash scripts/web.sh</code>, or set <code>BRAID_API</code> if it is
          running somewhere other than <code>http://127.0.0.1:8080</code>.
        </p>
      </Card>
    );
  }
  if (worldsLoading || !world) return <Loading>Loading venue state</Loading>;

  return (
    <>
      <Controls
        amountIn={amountIn}
        slippageBps={slippageBps}
        onAmount={setAmountIn}
        onSlippage={setSlippageBps}
      />

      {plan.error ? (
        <Card title="Could not plan this order">
          <p className="note">{plan.error}</p>
        </Card>
      ) : null}

      {plan.data ? (
        <>
          <Headline plan={plan.data} />
          <Split plan={plan.data} />
        </>
      ) : plan.loading ? (
        <Loading>Planning</Loading>
      ) : null}

      <Card
        title="How each venue prices size"
        sub="Every venue priced alone, and the split, across four decades of order size. Effective price is output per unit of input, so the venues are comparable at every size: the book’s flat stretches are its whole-lot steps, and the concentrated pool falls away where it runs out of range. Click a name to hide it."
      >
        {curves.data ? (
          <CurveChart
            curves={curves.data}
            hidden={hidden}
            setHidden={setHidden}
            mode={curveMode}
            setMode={setCurveMode}
          />
        ) : curves.error ? (
          <Empty>{curves.error}</Empty>
        ) : (
          <Loading>Sampling curves</Loading>
        )}
      </Card>

      {plan.data ? <ExecutePanel plan={plan.data} world={world} /> : null}
    </>
  );
}

// -------------------------------------------------------------- controls -- //

function Controls({
  amountIn,
  slippageBps,
  onAmount,
  onSlippage,
}: {
  amountIn: number;
  slippageBps: number;
  onAmount: (n: number) => void;
  onSlippage: (n: number) => void;
}) {
  const [draft, setDraft] = useState(String(amountIn));
  const toast = useToast();

  function commit() {
    const v = Number(draft.replace(/[, _]/g, ''));
    if (!Number.isFinite(v) || v <= 0) {
      toast('Amount must be a positive whole number.', 'bad');
      setDraft(String(amountIn));
      return;
    }
    onAmount(Math.floor(v));
    setDraft(String(Math.floor(v)));
  }

  function choose(p: number) {
    onAmount(p);
    setDraft(String(p));
  }

  return (
    <Card
      title="Plan an order"
      sub="The split is decided in Rust, against the state each venue prices from. Venues do not interact, so the total is exactly the sum of each leg — which is what lets the plan be enforced to the unit on chain."
    >
      <div className="row">
        <label className="field grow">
          <span>Amount in (TUSD base units)</span>
          <input
            type="text"
            inputMode="numeric"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commit();
            }}
          />
        </label>
        <label className="field">
          <span>Slippage (bps)</span>
          <input
            type="number"
            min={0}
            max={10_000}
            value={slippageBps}
            onChange={(e) => {
              const v = Number(e.target.value);
              onSlippage(Number.isFinite(v) ? Math.max(0, Math.min(10_000, Math.floor(v))) : 0);
            }}
          />
        </label>
      </div>

      <div className="hint">Presets</div>
      <div className="row tight" style={{ marginTop: 6 }}>
        {PRESETS.map((p) => (
          <button
            key={p}
            type="button"
            className={`btn sm${p === amountIn ? ' primary' : ' ghost'}`}
            onClick={() => choose(p)}
          >
            {fmt(p)}
          </button>
        ))}
      </div>
    </Card>
  );
}

// -------------------------------------------------------------- headline -- //

function Headline({ plan }: { plan: Plan }) {
  const best = plan.bestFillingWholeOrder;
  return (
    <Card>
      <div className="grid four">
        <Stat label="Total out" value={fmt(plan.totalOut)} note={`for ${fmt(plan.amountIn)} in`} hero />
        {best ? (
          <Stat
            label={`vs ${venueLabel(best.venue)} alone`}
            value={`+${pct(best.gainPct)}`}
            note={`+${fmt(best.gain)} over the best venue that fills the whole order`}
            good
          />
        ) : (
          <Stat
            label="vs one venue"
            value="—"
            note="no single venue can fill the whole order at this size"
            small
          />
        )}
        <Stat
          label="min_out"
          value={fmt(plan.minOut)}
          small
          note={
            plan.slippageBps === 0
              ? 'zero slippage: the chain must pay the prediction exactly'
              : `${plan.slippageBps} bps below the plan`
          }
        />
        <Stat
          label="Unspent"
          value={fmt(plan.unspent)}
          small
          note={plan.unspent === 0 ? 'every unit was placed' : 'returned by the route'}
        />
      </div>
    </Card>
  );
}

// ----------------------------------------------------------------- split -- //

function Split({ plan }: { plan: Plan }) {
  const marginals = plan.legs.map((l) => l.marginal).filter((m): m is number => typeof m === 'number');
  const spread = marginals.length > 1 ? Math.max(...marginals) - Math.min(...marginals) : 0;
  const idle = plan.idleVenues.filter((v) => typeof v.marginal === 'number');

  if (!plan.legs.length) {
    return (
      <Card title="The split">
        <Empty>No venue can price an order this size.</Empty>
      </Card>
    );
  }

  return (
    <Card title="The split">
      <SplitBar legs={plan.legs} />
      <div style={{ height: 16 }} />

      <Table
        rowKey={(r) => r.venue}
        columns={[
          {
            head: 'Venue',
            render: (r) => (
              <>
                <Swatch color={venueColor(r.venue)} />
                {venueLabel(r.venue)}
              </>
            ),
          },
          { head: 'Offered', num: true, render: (r) => fmt(r.amount) },
          { head: 'Consumed', num: true, render: (r) => fmt(r.spent) },
          { head: 'Out', num: true, render: (r) => fmt(r.out) },
          { head: 'Share', num: true, render: (r) => pct(r.share) },
          { head: 'Eff. price', num: true, render: (r) => r.effectivePrice.toFixed(6) },
          {
            head: 'Marginal',
            num: true,
            render: (r) => (typeof r.marginal === 'number' ? r.marginal.toFixed(6) : '—'),
          },
        ]}
        rows={plan.legs}
        footer={
          <tr>
            <td>Total</td>
            <td className="num">{fmt(plan.amountIn)}</td>
            <td className="num">{fmt(plan.amountIn - plan.unspent)}</td>
            <td className="num">{fmt(plan.totalOut)}</td>
            <td className="num">100.00%</td>
            <td className="num">
              {(plan.totalOut / Math.max(plan.amountIn - plan.unspent, 1)).toFixed(6)}
            </td>
            <td className="num" />
          </tr>
        }
      />

      <p className="hint">
        Marginal is output for one more unit at that allocation, per unit consumed — probed by
        finite difference, because these curves are integer staircases and the book is flat inside a
        level. The optimizer stops when they are as equal as the steps allow
        {marginals.length > 1 ? `; the spread here is ${spread.toExponential(2)}.` : '.'}
      </p>

      {idle.length ? (
        <p className="hint">
          Not used:{' '}
          {idle.map((v, i) => (
            <span key={v.venue}>
              {i ? ', ' : ''}
              <Swatch color={venueColor(v.venue)} />
              {venueLabel(v.venue)} would pay {v.marginal!.toFixed(6)} for the next unit
            </span>
          ))}
          .
        </p>
      ) : null}

      <div style={{ marginTop: 18 }}>
        <h3 style={{ fontSize: 14, margin: '0 0 10px' }}>Each venue taking the whole order alone</h3>
        <Table
          rowKey={(r) => r.venue}
          columns={[
            {
              head: 'Venue',
              render: (r) => (
                <>
                  <Swatch color={venueColor(r.venue)} />
                  {venueLabel(r.venue)}
                </>
              ),
            },
            { head: 'Out', num: true, render: (r) => fmt(r.out) },
            { head: 'Consumed', num: true, render: (r) => fmt(r.spent) },
            {
              head: 'Fills it?',
              render: (r) =>
                r.fillsWholeOrder ? <Pill kind="good">yes</Pill> : <Pill kind="warn">runs out of depth</Pill>,
            },
          ]}
          rows={plan.allIn}
        />
      </div>
    </Card>
  );
}

// ---------------------------------------------------------------- curves -- //

type CurveMode = 'price' | 'out';

function CurveChart({
  curves,
  hidden,
  setHidden,
  mode,
  setMode,
}: {
  curves: Curves;
  hidden: Set<string>;
  setHidden: (s: Set<string>) => void;
  mode: CurveMode;
  setMode: (m: CurveMode) => void;
}) {
  const series = useMemo<Series[]>(() => {
    // Effective price is out/in. A venue that cannot price a size at all pays
    // nothing and shows as zero, which is the honest reading: below its dust
    // threshold the venue is unusable, not merely expensive.
    const y = (p: { in: number; out: number }) => (mode === 'price' ? p.out / Math.max(p.in, 1) : p.out);

    const venues: Series[] = curves.venues.map((s) => ({
      key: s.venue,
      label: venueLabel(s.venue),
      color: venueColor(s.venue),
      points: s.points.map((p) => ({ x: p.in, y: y(p) })),
    }));
    if (curves.route) {
      venues.unshift({
        key: 'route',
        label: 'Route',
        color: venueColor('route'),
        thick: true,
        points: curves.route.map((p) => ({ x: p.in, y: y(p) })),
      });
    }
    return venues;
  }, [curves, mode]);

  function toggle(key: string) {
    const next = new Set(hidden);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    setHidden(next);
  }

  return (
    <>
      <div className="row between" style={{ marginBottom: 4 }}>
        <Legend series={series} hidden={hidden} onToggle={toggle} />
        <div className="row tight">
          <button
            type="button"
            className={`btn sm${mode === 'price' ? ' primary' : ' ghost'}`}
            onClick={() => setMode('price')}
          >
            Effective price
          </button>
          <button
            type="button"
            className={`btn sm${mode === 'out' ? ' primary' : ' ghost'}`}
            onClick={() => setMode('out')}
          >
            Amount out
          </button>
        </div>
      </div>
      <LineChart
        series={series}
        hidden={hidden}
        xTitle="amount in (log scale)"
        yTitle={mode === 'price' ? 'out per unit in' : 'amount out'}
        yFormat={mode === 'price' ? (n) => n.toFixed(4) : compact}
      />
    </>
  );
}
