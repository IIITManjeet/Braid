'use client';

import { useEffect, useState } from 'react';
import { useWorld } from './WorldProvider';

export default function TopBar() {
  const { worlds, world, worldId, setWorldId, refresh, refreshing, canRefresh } = useWorld();

  return (
    <>
      <header className="topbar">
        <div className="brand">
          <svg className="mark" viewBox="0 0 32 32" aria-hidden>
            <path
              d="M2 16c6-10 6 10 12 0s6 10 12 0"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeLinecap="round"
            />
          </svg>
          <div>
            <span className="brand-name">Braid</span>
            <span className="brand-sub">one order, four venues, two Move chains</span>
          </div>
        </div>

        <div className="topbar-controls">
          <label className="field compact">
            <span>Venue state</span>
            <select
              value={worldId}
              onChange={(e) => setWorldId(e.target.value)}
              disabled={!worlds.length}
            >
              {worlds.length ? (
                worlds.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.label}
                  </option>
                ))
              ) : (
                <option>Loading…</option>
              )}
            </select>
          </label>

          {canRefresh ? (
            <button
              type="button"
              className="btn ghost"
              onClick={refresh}
              disabled={refreshing}
              title="Re-read live Sui pool state through scripts/route.py"
            >
              {refreshing ? 'Reading chain…' : 'Refresh chain'}
            </button>
          ) : null}

          <ThemeToggle />
        </div>
      </header>

      {world ? <Banner /> : null}
    </>
  );
}

function Banner() {
  const { world, refresh, refreshing, canRefresh } = useWorld();
  if (!world) return null;

  if (world.live) {
    return (
      <div className="banner live">
        <strong>Live. </strong>
        {world.description} Source: {world.source}.
      </div>
    );
  }
  if (world.executable) {
    return (
      <div className="banner">
        <strong>Historical snapshot. </strong>
        {world.description}{' '}
        {canRefresh ? (
          <button type="button" className="btn ghost sm" onClick={refresh} disabled={refreshing}>
            Refresh now
          </button>
        ) : (
          <>
            Reading live state needs the Sui CLI, which this deployment does not carry — run it
            locally with <code>bash scripts/web.sh</code> for that.
          </>
        )}
      </div>
    );
  }
  return (
    <div className="banner">
      <strong>Offline fixture. </strong>
      {world.description}
    </div>
  );
}

function ThemeToggle() {
  const [theme, setTheme] = useState<'dark' | 'light'>('dark');

  useEffect(() => {
    const stored = window.localStorage.getItem('braid.theme') as 'dark' | 'light' | null;
    const initial =
      stored ?? (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    setTheme(initial);
    document.documentElement.dataset.theme = initial;
  }, []);

  function toggle() {
    const next = theme === 'dark' ? 'light' : 'dark';
    setTheme(next);
    document.documentElement.dataset.theme = next;
    window.localStorage.setItem('braid.theme', next);
  }

  return (
    <button
      type="button"
      className="btn icon"
      onClick={toggle}
      title="Toggle light and dark"
      aria-label="Toggle theme"
    >
      <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2">
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" />
      </svg>
    </button>
  );
}
