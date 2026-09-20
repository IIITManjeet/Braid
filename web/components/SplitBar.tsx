'use client';

import type { Leg } from '@/lib/api';
import { venueColor, venueLabel } from '@/lib/venues';
import { pct } from '@/lib/format';

/**
 * One stacked bar, a segment per leg, sized by what each venue consumed.
 *
 * Segments are separated by a surface-coloured gap so two adjacent legs never
 * read as one. Percentages are drawn only where the segment is wide enough to
 * hold the text.
 */
export default function SplitBar({ legs }: { legs: Leg[] }) {
  return (
    <div className="splitbar">
      {legs.map((l) => (
        <div
          key={l.venue}
          style={{ flexGrow: Math.max(l.spent, 1), background: venueColor(l.venue) }}
          title={`${venueLabel(l.venue)} ${pct(l.share, 1)}`}
        >
          {l.share > 0.07 ? <span className="pct">{pct(l.share, 0)}</span> : null}
        </div>
      ))}
    </div>
  );
}
