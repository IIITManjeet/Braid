'use client';

import { useRef, useState } from 'react';
import { compact, fmt } from '@/lib/format';

export type BarRow = { label: string; value: number; color: string; note?: string };

const ROW_H = 30;
const PAD = 8;
const LABEL_W = 132;
const VALUE_W = 92;

/**
 * Horizontal bars: the form for comparing magnitude across named categories,
 * and the one that leaves room for the names.
 *
 * Bars are anchored to the baseline with rounded data-ends and a gap between
 * neighbours, so adjacent bars never read as one shape.
 */
export default function BarsH({
  rows,
  unit = 'value',
  valueFormat = compact,
  width = 900,
}: {
  rows: BarRow[];
  unit?: string;
  valueFormat?: (n: number) => string;
  /**
   * viewBox width. Everything, text included, scales by container/viewBox, so
   * a chart placed in a half-width column needs a smaller number here or its
   * labels come out too small to read.
   */
  width?: number;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const [hover, setHover] = useState<{ row: BarRow; px: number; py: number } | null>(null);

  const W = width;
  const H = rows.length * ROW_H + PAD * 2;
  const iw = W - LABEL_W - VALUE_W;
  const max = Math.max(1, ...rows.map((r) => r.value));

  const hostW = hostRef.current?.clientWidth ?? 900;
  const tipLeft = hover ? Math.min(Math.max(hover.px + 12, 0), Math.max(hostW - 190, 0)) : 0;

  return (
    <div className="chart" ref={hostRef}>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" role="img">
        {rows.map((r, i) => {
          const y = PAD + i * ROW_H;
          const w = Math.max(2, (r.value / max) * iw);
          return (
            <g key={`${r.label}-${i}`}>
              <text
                className="axis-text"
                x={0}
                y={y + ROW_H / 2 + 4}
                fill="var(--text-secondary)"
              >
                {r.label}
              </text>
              <rect
                x={LABEL_W}
                y={y + 5}
                width={w}
                height={ROW_H - 13}
                rx={4}
                fill={r.color}
                pointerEvents="all"
                onPointerEnter={(ev) => {
                  const svg = (ev.target as SVGRectElement).ownerSVGElement;
                  if (!svg) return;
                  const b = svg.getBoundingClientRect();
                  setHover({
                    row: r,
                    px: ((LABEL_W + w) / W) * b.width,
                    py: ((y + ROW_H / 2) / H) * b.height,
                  });
                }}
                onPointerLeave={() => setHover(null)}
              />
              <text
                className="axis-text"
                x={LABEL_W + w + 10}
                y={y + ROW_H / 2 + 4}
                fill="var(--text-primary)"
              >
                {valueFormat(r.value)}
              </text>
            </g>
          );
        })}
      </svg>

      {hover ? (
        <div className="tip" style={{ left: tipLeft, top: Math.max(hover.py - 30, 0) }}>
          <div className="tip-head">{hover.row.label}</div>
          <div className="tip-row">
            <span className="k">{unit}</span>
            <span className="v">{fmt(hover.row.value)}</span>
          </div>
          {hover.row.note ? <div className="tip-row"><span className="k">{hover.row.note}</span></div> : null}
        </div>
      ) : null}
    </div>
  );
}
