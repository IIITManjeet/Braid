'use client';

import { useMemo, useRef, useState } from 'react';
import { compact, fmt } from '@/lib/format';

export type Series = {
  key: string;
  label: string;
  color: string;
  points: { x: number; y: number }[];
  thick?: boolean;
};

type Props = {
  series: Series[];
  hidden?: Set<string>;
  xTitle?: string;
  yTitle?: string;
  height?: number;
  /** How to format a y value in the tooltip and on the axis. */
  yFormat?: (n: number) => string;
};

const W = 900;
const M = { t: 16, r: 78, b: 42, l: 72 };

/** Round a step up to the nearest 1, 2 or 5 times a power of ten. */
function niceStep(raw: number): number {
  if (!(raw > 0)) return 1;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const norm = raw / mag;
  return (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag;
}

/** Gridline values on round numbers, covering [min, max]. */
function niceTicks(min: number, max: number, target = 5): number[] {
  const step = niceStep((max - min) / target);
  const first = Math.ceil(min / step) * step;
  const out: number[] = [];
  for (let v = first; v <= max + step * 1e-6; v += step) out.push(Number(v.toFixed(10)));
  return out.length ? out : [min, max];
}

/**
 * Output against order size.
 *
 * The x axis is logarithmic because the structure worth seeing -- a book's
 * whole-lot steps, a concentrated pool running out of range -- is spread over
 * decades, and a linear sweep spends every pixel in the last one.
 */
export default function LineChart({
  series,
  hidden,
  xTitle,
  yTitle,
  height = 320,
  yFormat = compact,
}: Props) {
  const hostRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const [cursor, setCursor] = useState<{ index: number; px: number; py: number } | null>(null);

  const H = height;
  const iw = W - M.l - M.r;
  const ih = H - M.t - M.b;

  const shown = useMemo(
    () => series.filter((s) => !hidden?.has(s.key) && s.points.length > 0),
    [series, hidden],
  );

  const scale = useMemo(() => {
    const all = shown.length ? shown : series;
    const xs = all.flatMap((s) => s.points.map((p) => p.x)).filter((x) => x > 0);
    const ys = all.flatMap((s) => s.points.map((p) => p.y));
    const xMin = xs.length ? Math.max(1, Math.min(...xs)) : 1;
    const xMax = xs.length ? Math.max(...xs, xMin * 10) : 10;
    // The floor is the data's own minimum, not zero: an effective-price series
    // lives in a narrow band near 1, and anchoring it to zero would flatten
    // every difference worth seeing into one line.
    const rawMax = ys.length ? Math.max(...ys) : 1;
    const rawMin = ys.length ? Math.min(...ys) : 0;
    const pad = (rawMax - rawMin) * 0.06 || rawMax * 0.06 || 1;
    const yMax = rawMax + pad;
    const yMin = Math.max(0, rawMin - pad);
    const lx = (x: number) => Math.log10(Math.max(x, 1));
    const span = Math.max(lx(xMax) - lx(xMin), 1e-9);
    const yspan = Math.max(yMax - yMin, 1e-12);
    return {
      xMin,
      xMax,
      yMax,
      yMin,
      lx,
      sx: (x: number) => M.l + ((lx(x) - lx(xMin)) / span) * iw,
      sy: (y: number) => M.t + ih - ((y - yMin) / yspan) * ih,
    };
  }, [shown, series, iw, ih]);

  const { sx, sy, yMax, yMin, xMin, xMax, lx } = scale;

  const yTicks = useMemo(() => niceTicks(yMin, yMax), [yMax, yMin]);
  const xTicks = useMemo(() => {
    const out: number[] = [];
    for (let d = Math.ceil(lx(xMin)); d <= Math.floor(lx(xMax)); d++) out.push(10 ** d);
    return out;
  }, [lx, xMin, xMax]);

  // Every series is sampled at the same sizes, so one index serves all of them.
  const ref = shown[0]?.points ?? [];

  const LABEL_GAP = 13;
  const labelRows = useMemo(() => {
    const rows = shown
      .map((s) => {
        const last = s.points[s.points.length - 1];
        return { key: s.key, label: s.label, color: s.color, x: sx(last.x) + 8, y: sy(last.y) + 4 };
      })
      .sort((a, b) => a.y - b.y);
    // One downward pass opens any gap smaller than a line, then a clamp keeps
    // the last one inside the box.
    for (let i = 1; i < rows.length; i++) {
      if (rows[i].y - rows[i - 1].y < LABEL_GAP) rows[i].y = rows[i - 1].y + LABEL_GAP;
    }
    const overflow = rows.length ? rows[rows.length - 1].y - (H - 6) : 0;
    if (overflow > 0) for (const r of rows) r.y -= overflow;
    return rows;
  }, [shown, sx, sy, H]);

  function onMove(ev: React.PointerEvent<SVGSVGElement>) {
    const svg = svgRef.current;
    if (!svg || !ref.length) return;
    const b = svg.getBoundingClientRect();
    const vx = ((ev.clientX - b.left) / b.width) * W;
    const vy = ((ev.clientY - b.top) / b.height) * H;
    if (vx < M.l || vx > M.l + iw) {
      setCursor(null);
      return;
    }
    let bi = 0;
    let bd = Infinity;
    ref.forEach((p, i) => {
      const d = Math.abs(sx(p.x) - vx);
      if (d < bd) {
        bd = d;
        bi = i;
      }
    });
    setCursor({ index: bi, px: (sx(ref[bi].x) / W) * b.width, py: (vy / H) * b.height });
  }

  const tipRows = cursor
    ? shown
        .map((s) => ({ s, p: s.points[cursor.index] }))
        .filter((r) => r.p)
        .sort((a, b) => b.p.y - a.p.y)
    : [];

  // Keep the tooltip inside the chart box.
  const hostW = hostRef.current?.clientWidth ?? 900;
  const tipLeft = cursor ? Math.min(Math.max(cursor.px + 14, 0), Math.max(hostW - 190, 0)) : 0;

  return (
    <div className="chart" ref={hostRef}>
      <svg
        ref={svgRef}
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={yTitle ? `${yTitle} against ${xTitle}` : 'chart'}
        onPointerMove={onMove}
        onPointerLeave={() => setCursor(null)}
      >
        {yTicks.map((v, i) => (
          <g key={`y${i}`}>
            <line className="grid-line" x1={M.l} x2={M.l + iw} y1={sy(v)} y2={sy(v)} />
            <text className="axis-text" x={M.l - 9} y={sy(v) + 3.5} textAnchor="end">
              {yFormat(v)}
            </text>
          </g>
        ))}

        {xTicks.map((v) => (
          <g key={`x${v}`}>
            <line className="grid-line" x1={sx(v)} x2={sx(v)} y1={M.t} y2={M.t + ih} />
            <text className="axis-text" x={sx(v)} y={M.t + ih + 16} textAnchor="middle">
              {compact(v)}
            </text>
          </g>
        ))}

        <line className="axis-line" x1={M.l} x2={M.l + iw} y1={M.t + ih} y2={M.t + ih} />

        {xTitle ? (
          <text className="axis-title" x={M.l + iw / 2} y={H - 4} textAnchor="middle">
            {xTitle}
          </text>
        ) : null}
        {yTitle ? (
          <text
            className="axis-title"
            x={13}
            y={M.t + ih / 2}
            textAnchor="middle"
            transform={`rotate(-90 13 ${M.t + ih / 2})`}
          >
            {yTitle}
          </text>
        ) : null}

        {shown.map((s) => {
          const d = s.points
            .map((p, i) => `${i ? 'L' : 'M'}${sx(p.x).toFixed(2)},${sy(p.y).toFixed(2)}`)
            .join('');
          return <path key={s.key} className={`series-line${s.thick ? ' thick' : ''}`} d={d} stroke={s.color} />;
        })}

        {/* Direct labels: identity without reading the legend, and the relief
            the light-mode contrast check asks for. Series that end close
            together are pushed apart so none is printed over another. */}
        {labelRows.map((l) => (
          <text key={l.key} className="direct-label" x={l.x} y={l.y} fill={l.color}>
            {l.label}
          </text>
        ))}

        {cursor && ref[cursor.index] ? (
          <>
            <line
              className="crosshair"
              x1={sx(ref[cursor.index].x)}
              x2={sx(ref[cursor.index].x)}
              y1={M.t}
              y2={M.t + ih}
            />
            {tipRows.map(({ s, p }) => (
              <circle key={s.key} className="dot" cx={sx(p.x)} cy={sy(p.y)} r={4.5} fill={s.color} />
            ))}
          </>
        ) : null}
      </svg>

      {cursor && ref[cursor.index] ? (
        <div className="tip" style={{ left: tipLeft, top: Math.max(cursor.py - 40, 0) }}>
          <div className="tip-head">in {fmt(ref[cursor.index].x)}</div>
          {tipRows.map(({ s, p }) => (
            <div className="tip-row" key={s.key}>
              <span className="k">
                <span className="swatch" style={{ background: s.color }} />
                {s.label}
              </span>
              <span className="v">{yFormat(p.y)}</span>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

/** A legend that also toggles series. Always present for two or more series. */
export function Legend({
  series,
  hidden,
  onToggle,
}: {
  series: Series[];
  hidden: Set<string>;
  onToggle: (key: string) => void;
}) {
  return (
    <ul className="legend">
      {series.map((s) => (
        <li key={s.key} className={hidden.has(s.key) ? 'off' : ''}>
          <button type="button" aria-pressed={!hidden.has(s.key)} onClick={() => onToggle(s.key)}>
            <span className="swatch" style={{ background: s.color }} />
            <span>{s.label}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}
