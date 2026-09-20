// Number formatting, shared by tables, tiles and chart axes.

export function fmt(n: number | null | undefined, digits = 0): string {
  if (n === null || n === undefined || Number.isNaN(n)) return '—';
  return Number(n).toLocaleString('en-US', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

/** Compact axis labels: 16M rather than 16,000,000. */
export function compact(n: number): string {
  const a = Math.abs(n);
  if (a >= 1e9) return (n / 1e9).toFixed(a >= 1e10 ? 0 : 1).replace(/\.0$/, '') + 'B';
  if (a >= 1e6) return (n / 1e6).toFixed(a >= 1e7 ? 0 : 1).replace(/\.0$/, '') + 'M';
  if (a >= 1e3) return (n / 1e3).toFixed(a >= 1e4 ? 0 : 1).replace(/\.0$/, '') + 'k';
  return String(Math.round(n));
}

/** 0x1234…abcd, for an address that must stay recognisable but not wrap. */
export function shortAddr(a: string | null | undefined, keep = 6): string {
  if (!a || typeof a !== 'string') return '—';
  const s = a.startsWith('0x') ? a : `0x${a}`;
  if (s.length <= keep * 2 + 4) return s;
  return `${s.slice(0, keep + 2)}…${s.slice(-keep)}`;
}

export const pct = (x: number, digits = 2) => `${(x * 100).toFixed(digits)}%`;
