// Venue identity: which colour and which name mean which venue.
//
// Colour follows the entity and never its rank, so these are fixed here rather
// than assigned in whatever order a plan happens to list its legs. A filter
// that hides a series must not repaint the survivors.
//
// Slot 1 goes to the route because it is the headline series; the four venues
// take slots 2-5. The ordering is the colour-vision-deficiency safety
// mechanism -- every adjacent pair was validated against both surfaces -- so
// re-ordering these is not a cosmetic change.

import type { VenueKind } from './api';

type Identity = { label: string; color: string };

export const VENUE: Record<string, Identity> = {
  route:  { label: 'Route',  color: 'var(--series-1)' },
  cpmm:   { label: 'CPMM',   color: 'var(--series-2)' },
  stable: { label: 'Stable', color: 'var(--series-3)' },
  clmm:   { label: 'CLMM',   color: 'var(--series-4)' },
  clob:   { label: 'CLOB',   color: 'var(--series-5)' },
  // The router's generated suite is about the route, so it wears the route's
  // colour rather than a fifth venue hue.
  router: { label: 'Router', color: 'var(--series-1)' },
};

export const venueColor = (kind: string): string => VENUE[kind]?.color ?? 'var(--text-muted)';
export const venueLabel = (kind: string): string => VENUE[kind]?.label ?? kind;
export const isVenue = (kind: string): kind is VenueKind => kind in VENUE && kind !== 'route';
