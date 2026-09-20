/**
 * The pricing API is Rust. `braid-server` wraps `braid-quote` and `braid-route`
 * -- the crates the differential fuzzer checks against both Move VMs -- so
 * every quote and every split the page shows is the same code the generated
 * Move tests hold the chain to. None of it is reimplemented here.
 *
 * In development Next proxies `/api/*` to that server so the page is
 * same-origin and needs no CORS. Point BRAID_API somewhere else to run the
 * frontend against a server on another host.
 */
const API = process.env.BRAID_API ?? 'http://127.0.0.1:8080';

/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [{ source: '/api/:path*', destination: `${API}/api/:path*` }];
  },
};

export default nextConfig;
