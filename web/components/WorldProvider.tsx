'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

import { getHealth, getWorlds, refreshChain, type World } from '@/lib/api';
import { useToast } from './ui';

type WorldState = {
  worlds: World[];
  world: World | null;
  worldId: string;
  setWorldId: (id: string) => void;
  loading: boolean;
  error: string | null;
  refreshing: boolean;
  refresh: () => Promise<void>;
  /** Whether this server can read live chain state at all. */
  canRefresh: boolean;
};

const Context = createContext<WorldState | null>(null);

export function useWorld(): WorldState {
  const ctx = useContext(Context);
  if (!ctx) throw new Error('useWorld outside WorldProvider');
  return ctx;
}

const STORAGE_KEY = 'braid.world';

export function WorldProvider({ children }: { children: ReactNode }) {
  const [worlds, setWorlds] = useState<World[]>([]);
  const [worldId, setWorldIdState] = useState('test-world');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  // Assumed false until the server says otherwise, so a deployed build never
  // flashes a control it cannot honour.
  const [canRefresh, setCanRefresh] = useState(false);
  const toast = useToast();

  const load = useCallback(async () => {
    const list = await getWorlds();
    setWorlds(list);
    setWorldIdState((current) => (list.some((w) => w.id === current) ? current : list[0]?.id ?? current));
    return list;
  }, []);

  useEffect(() => {
    // Read the stored choice after mount: server and client must agree on the
    // first render, and localStorage does not exist during it.
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored) setWorldIdState(stored);

    getHealth()
      .then((h) => setCanRefresh(h.canRefresh))
      .catch(() => setCanRefresh(false));

    load()
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setLoading(false));
  }, [load]);

  const setWorldId = useCallback((id: string) => {
    setWorldIdState(id);
    window.localStorage.setItem(STORAGE_KEY, id);
  }, []);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await refreshChain();
      await load();
      setWorldId('sui-testnet');
      toast('Live Sui state read. This snapshot is safe to execute against.', 'good');
    } catch (e) {
      toast(`Could not read the chain: ${e instanceof Error ? e.message : String(e)}`, 'bad', 9000);
    } finally {
      setRefreshing(false);
    }
  }, [load, setWorldId, toast]);

  const value = useMemo<WorldState>(
    () => ({
      worlds,
      world: worlds.find((w) => w.id === worldId) ?? worlds[0] ?? null,
      worldId,
      setWorldId,
      loading,
      error,
      refreshing,
      refresh,
      canRefresh,
    }),
    [worlds, worldId, setWorldId, loading, error, refreshing, refresh, canRefresh],
  );

  return <Context.Provider value={value}>{children}</Context.Provider>;
}
