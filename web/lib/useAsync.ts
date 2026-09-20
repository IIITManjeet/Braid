'use client';

import { useEffect, useState } from 'react';

type Result<T> = { data: T | null; error: string | null; loading: boolean };

/**
 * Run an async fetch when `deps` change, discarding any result that a newer
 * call has already superseded. Without the guard a slow request for an old
 * order size can land after a fast one for the current size and overwrite it.
 */
export function useAsync<T>(fn: () => Promise<T>, deps: unknown[]): Result<T> {
  const [state, setState] = useState<Result<T>>({ data: null, error: null, loading: true });

  useEffect(() => {
    let live = true;
    setState((s) => ({ ...s, loading: true, error: null }));
    fn()
      .then((data) => live && setState({ data, error: null, loading: false }))
      .catch((e: unknown) =>
        live && setState({ data: null, error: e instanceof Error ? e.message : String(e), loading: false }),
      );
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return state;
}
