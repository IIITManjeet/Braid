# Braid, as one image: the Rust API and the Next.js page that draws it.
#
#   docker build -t braid .
#   docker run -p 3000:3000 braid      # http://localhost:3000
#
# Both processes run behind one origin, so /api/* is same-origin and no CORS is
# involved -- the same arrangement `scripts/web.sh` sets up locally.
#
# Alpine throughout, which means the API is built against musl rather than
# glibc. Nothing in braid-server links C: axum, tokio, serde and ethnum are all
# pure Rust, so a static musl binary drops the runtime image to a base plus two
# executables, and takes most of the Debian CVE surface with it.
#
# What is deliberately *not* here: the vendored Sui CLI. It is ~800MB, and the
# only thing that needs it is reading live pool state. The server reports that
# through /api/health and the page hides its refresh control rather than
# offering one that cannot work; the committed snapshot and the offline router
# test world both work without it.

# --- the API ---------------------------------------------------------------- #

FROM rust:1.96-alpine AS rust

RUN apk add --no-cache musl-dev

WORKDIR /build
# The whole workspace: braid-server depends on braid-quote and braid-route by
# path, and Cargo wants every member's manifest to resolve the lockfile.
COPY node/Cargo.toml node/Cargo.lock ./
COPY node/crates ./crates
RUN cargo build --release -p braid-server

# --- the page --------------------------------------------------------------- #

FROM node:22-alpine AS web

WORKDIR /build
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
# Leaves a server plus only the modules it imports, at .next/standalone.
ENV BRAID_STANDALONE=1
RUN npm run build

# --- what actually ships ----------------------------------------------------- #

FROM node:22-alpine AS runtime

ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    BRAID_API_PORT=8080

WORKDIR /app

COPY --from=rust /build/target/release/braid-server /usr/local/bin/braid-server

COPY --from=web /build/.next/standalone ./
COPY --from=web /build/.next/static ./.next/static

# The data the API reads at request time. The generated corpora are included
# because the verification page counts them from the files rather than
# repeating a number, and that claim should stay true inside the image.
COPY deployments ./deployments
COPY bench/results ./bench/results
COPY move ./move

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Nothing here needs root.
USER node

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
