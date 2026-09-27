//! Braid's quote, route and deployment API.
//!
//!     cargo run -p braid-server                  # http://127.0.0.1:8080
//!     cargo run -p braid-server -- --port 9000 --root D:/move-blockchain
//!
//! The server is deliberately thin. It owns no pricing: every quote and every
//! split comes from `braid-quote` and `braid-route`, the crates the
//! differential fuzzer checks against both Move VMs. If a number it served
//! were wrong, it would be wrong in the generated Move tests too.
//!
//! The front end is a separate Next.js app in `web/`, which proxies `/api/*`
//! here. Serving it from this binary was tried and dropped: two build systems
//! in one process buys nothing, and `next dev` needs to own its own port to
//! do hot reloading.

mod api;
mod repo;
#[cfg(test)]
mod tests;
mod world;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;


struct Args {
    port: u16,
    root: Option<PathBuf>,
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args { port: 8080, root: None };
    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--port" | "-p" => {
                let v = it.next().ok_or("--port needs a value")?;
                args.port = v.parse().map_err(|_| format!("bad port `{v}`"))?;
            }
            "--root" => args.root = Some(PathBuf::from(it.next().ok_or("--root needs a value")?)),
            "-h" | "--help" => return Err("help".into()),
            other => return Err(format!("unknown argument `{other}`")),
        }
    }
    Ok(args)
}

const USAGE: &str = "\
braid-server -- Braid's quote, route and deployment API

    cargo run -p braid-server -- [--port N] [--root DIR]

    --port N     port to listen on (default 8080)
    --root DIR   the Braid checkout to read deployments and benchmarks from
                 (default: found by walking up from the working directory)

The front end lives in web/ and proxies /api/* here. Run both with
`bash scripts/web.sh`, or `npm run dev` from web/ against an already-running
server.
";

#[tokio::main]
async fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            if e == "help" {
                print!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            eprintln!("{e}\n\n{USAGE}");
            return ExitCode::FAILURE;
        }
    };

    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let root = match args.root.or_else(|| repo::find_root(&cwd)) {
        Some(r) => r,
        None => {
            eprintln!(
                "could not find the Braid checkout above {}.\n\
                 Run from inside it, or pass --root.",
                cwd.display()
            );
            return ExitCode::FAILURE;
        }
    };
    let state = Arc::new(api::AppState::new(root.clone()));

    let app = api::router(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], args.port));
    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("could not bind {addr}: {e}");
            return ExitCode::FAILURE;
        }
    };

    println!("braid-server");
    println!("  checkout  {}", root.display());
    println!("  listening http://{addr}");
    println!("  press ctrl-c to stop");

    let served = axum::serve(listener, app).with_graceful_shutdown(async {
        let _ = tokio::signal::ctrl_c().await;
        println!("\nstopping");
    });
    if let Err(e) = served.await {
        eprintln!("server error: {e}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
