import type { Metadata } from 'next';
import type { ReactNode } from 'react';

import './globals.css';
import TopBar from '@/components/TopBar';
import Tabs from '@/components/Tabs';
import { ToastProvider } from '@/components/ui';
import { WorldProvider } from '@/components/WorldProvider';

export const metadata: Metadata = {
  title: 'Braid',
  description: 'A multi-venue on-chain exchange and router on Sui and Aptos Move.',
  icons: {
    icon:
      "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath d='M4 16c6-9 6 9 12 0s6 9 12 0' stroke='%233987e5' stroke-width='3' fill='none' stroke-linecap='round'/%3E%3C/svg%3E",
  },
};

// The theme is stamped before paint so a light-mode reader never sees a dark
// flash. It has to be inline: a module would not run early enough.
const THEME_SCRIPT = `
try {
  var t = localStorage.getItem('braid.theme')
    || (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
  document.documentElement.dataset.theme = t;
} catch (e) {}
`;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" data-theme="dark" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body>
        <ToastProvider>
          <WorldProvider>
            <TopBar />
            <Tabs />
            <main className="view">{children}</main>
            <footer className="foot">
              Every number here comes from <code>braid-quote</code> and <code>braid-route</code> —
              the same Rust the differential fuzzer checks against both Move VMs.
            </footer>
          </WorldProvider>
        </ToastProvider>
      </body>
    </html>
  );
}
