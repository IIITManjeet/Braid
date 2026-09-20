'use client';

import { getDifftest, type Suite } from '@/lib/api';
import { compact, fmt } from '@/lib/format';
import { useAsync } from '@/lib/useAsync';
import { venueColor, venueLabel } from '@/lib/venues';
import { Card, Empty, Loading, Pill, Stat, Swatch, Table } from '@/components/ui';
import BarsH from '@/components/charts/BarsH';

const base = (venue: string) => venue.replace('-pool', '');
const suiteLabel = (venue: string) =>
  `${venueLabel(base(venue))}${venue.endsWith('-pool') ? ' (pool)' : ''}`;

export default function VerificationPage() {
  const { data, error, loading } = useAsync(getDifftest, []);
  if (loading) return <Loading>Counting generated cases</Loading>;
  if (error || !data) return <Empty>{error ?? 'No generated corpora found.'}</Empty>;

  const formula = data.suites.filter((s) => s.kind === 'formula');
  const staged = data.suites.filter((s) => s.kind !== 'formula');

  return (
    <>
      <Card
        title="The headline test"
        sub="braid-quote is a Rust replica of the pricing math — a transliteration, not a reimplementation. Where the Move widens to u256 before dividing, so does the Rust; where it floor-divides twice rather than once by a product, so does the Rust. Floor division does not reassociate, so operation order is part of the spec. braid-difftest generates random states and trades, computes each answer with the replica, and emits them as Move tests. Both Move VMs then run every case, and a one-unit disagreement fails the build."
      >
        <div className="grid four">
          <Stat
            label="Formula cases"
            value={fmt(data.formulaCases)}
            note="individual checks, counted from the committed files"
            hero
          />
          <Stat
            label="Whole-state scenarios"
            value={fmt(data.scenarios)}
            note="random pools and books, quoted then executed"
            small
          />
          <Stat
            label="Optimizer plans"
            value={fmt(data.plans)}
            note="each run at a min_out equal to its prediction"
            small
          />
          <Stat
            label="Implementations × VMs"
            value="3 × 2"
            note="Rust replica, Sui Move, Aptos Move"
            small
          />
        </div>
      </Card>

      <Card
        title="Corpora, per venue"
        sub="The generated files are committed on purpose. The RNG is seeded, so regenerating produces an identical file unless a value moved — and then the diff names the case and the delta. A silent repricing becomes a reviewable line in a pull request."
      >
        {/* Formula suites and scenario suites are counted in different units, so
            they get their own chart rather than a shared bar length that would
            mean two different things. */}
        <div className="grid two">
          <div>
            <h3 style={{ fontSize: 13, margin: '0 0 8px' }}>Formula checks</h3>
            <Bars suites={formula} unit="assertions" />
          </div>
          <div>
            <h3 style={{ fontSize: 13, margin: '0 0 8px' }}>Scenarios and plans</h3>
            <Bars suites={staged} unit="test functions" />
          </div>
        </div>

        <div style={{ height: 8 }} />

        <Table
          rowKey={(s) => s.venue}
          columns={[
            {
              head: 'Suite',
              render: (s) => (
                <>
                  <Swatch color={venueColor(base(s.venue))} />
                  {s.venue}
                </>
              ),
            },
            { head: 'Kind', render: (s) => s.kind },
            { head: 'Sui', num: true, render: (s) => fmt(s.sui?.cases ?? 0) },
            { head: 'Aptos', num: true, render: (s) => fmt(s.aptos?.cases ?? 0) },
            { head: 'Assertions', num: true, render: (s) => fmt(s.sui?.asserts ?? 0) },
            { head: 'Test fns', num: true, render: (s) => fmt(s.sui?.tests ?? 0) },
            {
              head: 'Same file?',
              render: (s) =>
                s.identical ? (
                  <Pill kind="good">byte-identical</Pill>
                ) : (
                  <Pill kind="warn">rendered per dialect</Pill>
                ),
            },
          ]}
          rows={data.suites}
        />

        <p className="hint">
          The formula suites are emitted once and written to both trees unchanged, so <code>diff</code>{' '}
          between each pair is empty. The CLMM and CLOB scenario suites build chain state, so they
          are rendered per dialect from identically seeded streams: case k is the same pool and the
          same trades on either chain.
        </p>
      </Card>

      <Card title="What it does and does not prove">
        <div className="grid two">
          <div>
            <h3 style={{ fontSize: 13, margin: '0 0 6px' }}>Proves</h3>
            <p className="note">
              The implementations do not diverge. That catches a mis-transliterated operation order,
              a floor where the other has a ceil, a u128 intermediate where the other widened — the
              class of bug where the off-chain quote engine promises a price the chain will not
              honour.
            </p>
          </div>
          <div>
            <h3 style={{ fontSize: 13, margin: '0 0 6px' }}>Does not prove</h3>
            <p className="note">
              That either side is economically right. Two implementations can agree and both be
              wrong. That is covered separately — hand-derived fixtures, the invariant properties (k
              and D never decrease), and for StableSwap a third implementation in Python written
              from Curve’s published reference rather than from this code.
            </p>
          </div>
        </div>
        <p className="hint">
          The harness is verified against negative controls: flipping one mul_div_floor to
          mul_div_ceil in the replica fails the generated suite immediately, and letting the CLMM
          replica skip empty bitmap-word boundaries — walking a sorted tick list, as a natural
          reimplementation would — fails 58 of the 100 pool scenarios.
        </p>
      </Card>
    </>
  );
}

function Bars({ suites, unit }: { suites: Suite[]; unit: string }) {
  if (!suites.length) return <Empty>None.</Empty>;
  return (
    <BarsH
      rows={suites.map((s) => ({
        label: suiteLabel(s.venue),
        value: s.sui?.cases ?? 0,
        color: venueColor(base(s.venue)),
        note: `in ${s.package}`,
      }))}
      unit={unit}
      valueFormat={compact}
      width={430}
    />
  );
}
