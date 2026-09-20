'use client';

import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';

// --------------------------------------------------------------- pieces -- //

export function Card({
  title,
  sub,
  children,
  className = '',
}: {
  title?: ReactNode;
  sub?: ReactNode;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <section className={`card ${className}`}>
      {title ? <h2>{title}</h2> : null}
      {sub ? <p className="sub">{sub}</p> : null}
      {children}
    </section>
  );
}

export function Stat({
  label,
  value,
  note,
  hero = false,
  small = false,
  good = false,
}: {
  label: ReactNode;
  value: ReactNode;
  note?: ReactNode;
  hero?: boolean;
  small?: boolean;
  good?: boolean;
}) {
  return (
    <div className={`stat${hero ? ' hero' : ''}${good ? ' good' : ''}`}>
      <div className="label">{label}</div>
      <div className={`value${small ? ' sm' : ''}`}>{value}</div>
      {note ? <div className="note">{note}</div> : null}
    </div>
  );
}

export function Pill({ children, kind = '' }: { children: ReactNode; kind?: '' | 'good' | 'warn' | 'bad' }) {
  return <span className={`pill ${kind}`}>{children}</span>;
}

export function Swatch({ color }: { color: string }) {
  return <span className="swatch" style={{ background: color }} aria-hidden />;
}

export type Column<T> = {
  head: ReactNode;
  num?: boolean;
  render: (row: T) => ReactNode;
};

/**
 * A table view sits beside every chart on purpose: it is what makes the data
 * readable without colour, and the relief the light-mode contrast check asks
 * for on the lighter categorical slots.
 */
export function Table<T>({
  columns,
  rows,
  footer,
  rowKey,
}: {
  columns: Column<T>[];
  rows: T[];
  footer?: ReactNode;
  rowKey?: (row: T, i: number) => string;
}) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((c, i) => (
              <th key={i} className={c.num ? 'num' : ''}>
                {c.head}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={rowKey ? rowKey(r, i) : i}>
              {columns.map((c, j) => (
                <td key={j} className={c.num ? 'num' : ''}>
                  {c.render(r)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
        {footer ? <tfoot>{footer}</tfoot> : null}
      </table>
    </div>
  );
}

export function KV({ pairs }: { pairs: [ReactNode, ReactNode][] }) {
  return (
    <dl className="kv">
      {pairs
        .filter(([, v]) => v !== null && v !== undefined && v !== '')
        .map(([k, v], i) => (
          <div key={i} style={{ display: 'contents' }}>
            <dt>{k}</dt>
            <dd>{v}</dd>
          </div>
        ))}
    </dl>
  );
}

export function ExternalLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer">
      {children}
    </a>
  );
}

export function Raw({ label, value }: { label: string; value: unknown }) {
  return (
    <details className="raw">
      <summary>{label}</summary>
      <pre>{JSON.stringify(value, null, 2)}</pre>
    </details>
  );
}

export const Empty = ({ children }: { children: ReactNode }) => <div className="empty">{children}</div>;

export const Loading = ({ children = 'Loading' }: { children?: ReactNode }) => (
  <div className="empty">
    <span className="spinner" />
    {children}
  </div>
);

// ---------------------------------------------------------------- toast -- //

type ToastKind = '' | 'good' | 'bad';
type ToastFn = (message: ReactNode, kind?: ToastKind, ms?: number) => void;

const ToastContext = createContext<ToastFn>(() => {});
export const useToast = () => useContext(ToastContext);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<{ message: ReactNode; kind: ToastKind } | null>(null);

  const show = useCallback<ToastFn>((message, kind = '', ms = 5200) => {
    setToast({ message, kind });
    window.setTimeout(() => setToast(null), ms);
  }, []);

  const value = useMemo(() => show, [show]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      {toast ? (
        <div className={`toast ${toast.kind}`} role="status" aria-live="polite">
          {toast.message}
        </div>
      ) : null}
    </ToastContext.Provider>
  );
}
