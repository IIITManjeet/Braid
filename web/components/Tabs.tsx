'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const TABS = [
  { href: '/', label: 'Route' },
  { href: '/venues', label: 'Venues' },
  { href: '/deployments', label: 'Deployments' },
  { href: '/benchmarks', label: 'Benchmarks' },
  { href: '/verification', label: 'Verification' },
];

export default function Tabs() {
  const path = usePathname();
  return (
    <nav className="tabs">
      {TABS.map((t) => (
        <Link
          key={t.href}
          href={t.href}
          className="tab"
          aria-current={path === t.href ? 'page' : undefined}
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}
