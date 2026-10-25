//! The localhost bridge: the workspace webview talks ONLY to 127.0.0.1, and
//! this forwarder attaches the session cookie to every request it relays to
//! the ship. Webkit cookie policy therefore never matters. Builds that
//! withhold cookies on cross-site navigations, SW-mediated fetches, or
//! anything else all behave identically, because the webview needs no
//! cookies at all. One request per connection (Connection: close), bodies
//! streamed both ways, so the client's SSE beacon works.
//!
//! Lattice's bridge, with `lattice_fs` taken out of it: the session is got
//! here, by posting the +code to `/~/login` ourselves, and kept at
//! `config::cookie_file()` rather than in a path a CLI shares.
//!
//! Loopback is not a boundary. Any page in any browser on this machine can
//! aim requests at 127.0.0.1, and so can another account or a same-user app
//! sandboxed away from the cookie file. So the bridge relays only a request
//! that carries this launch's token: 256 random bits, handed to the
//! workspace webview once as an HttpOnly cookie on the bridge origin (see
//! `bootstrap_url`). Anything else gets a 403 and the ship never sees it.
//! Every auspex route is owner-only, so a request without the session has
//! nothing to relay to (security audit run-1).

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};

/// the ship base the bridge currently relays to, and the port it listens on
pub struct Bridge(pub Mutex<Option<(Arc<Mutex<String>>, u16)>>);

/// The webview's origin includes this port, and ALL web storage (the service
/// worker cache, localStorage) is keyed by origin. Binding port 0 gave every
/// launch a brand-new empty origin, so lattice's desktop app re-downloaded the
/// whole UI on every start and never got a warm cache; it was measurably
/// slower than the same UI in a browser, which keeps its origin. A
/// deterministic port is a stable origin, so the cache survives a restart.
/// auspex's client is a PWA with a service worker, so it wants this at least
/// as much.
///
/// BELOW 32768 on purpose. Linux hands out ephemeral ports from 32768 upward
/// (`net.ipv4.ip_local_port_range`), so a port inside that range can be held
/// by any unrelated outgoing connection at launch, the bind steps by one, and
/// the webview comes up on a DIFFERENT origin.
///
/// 26600, not lattice's 26500, so both apps can run side by side. Two apps
/// sharing a port base would race for it every launch and each would
/// intermittently find itself on the other's stepped port.
const PORT_BASE: u16 = 26600;
const PORT_SPAN: u16 = 16;

/// How long to keep asking for PORT_BASE before accepting a different origin.
/// Moving PORT_BASE below the ephemeral range stops the kernel taking it, but
/// leaves the likeliest thief of all: our own previous instance, still closing
/// its listener while the user relaunches. That is precisely the "quit,
/// rebuild, start again" path, and stepping a port there hands the new window
/// a new origin with an empty service-worker cache.
///
/// Waiting a few seconds costs a slow launch in a rare case.
const PORT_WAIT_MS: u64 = 3_000;
const PORT_POLL_MS: u64 = 100;

fn bind_stable() -> Result<(TcpListener, u16), String> {
    let mut last = String::new();
    //  the canonical origin, patiently
    for _ in 0..(PORT_WAIT_MS / PORT_POLL_MS) {
        match TcpListener::bind(("127.0.0.1", PORT_BASE)) {
            Ok(l) => return Ok((l, PORT_BASE)),
            Err(e) => last = e.to_string(),
        }
        std::thread::sleep(std::time::Duration::from_millis(PORT_POLL_MS));
    }
    //  Still held, so another instance is genuinely running rather than
    //  exiting. Stepping is right (a second window has to work) but it is a
    //  different origin, and the caller warns rather than letting the user
    //  discover it as a cold start.
    for port in PORT_BASE + 1..PORT_BASE + PORT_SPAN {
        match TcpListener::bind(("127.0.0.1", port)) {
            Ok(l) => return Ok((l, port)),
            Err(e) => last = e.to_string(),
        }
    }
    Err(format!(
        "bridge bind: no free port in {PORT_BASE}..{}: {last}",
        PORT_BASE + PORT_SPAN
    ))
}

/// Start (or re-point) the bridge for `ship_base`, a normalised base (see
/// `config::load_at`). Returns the local base URL.
pub fn ensure(state: &Bridge, ship_base: &str) -> Result<String, String> {
    let base = ship_base.to_string();
    let mut guard = state.0.lock().unwrap();
    if let Some((cur, port)) = guard.as_ref() {
        // Re-point the SAME listener instead of binding another one. The port
        // is part of the webview's origin, so rebinding would discard the
        // cache keyed to it. A ship change always comes from connect(), which
        // clears browsing data, so no ship is served another's cached shell.
        *cur.lock().unwrap() = base.clone();
        let port = *port;
        prewarm(&base);
        return Ok(format!("http://127.0.0.1:{port}"));
    }
    let (listener, port) = bind_stable()?;
    if port != PORT_BASE {
        // Not a cosmetic detail. Web storage is keyed by origin, so this
        // window shares nothing — service-worker cache included — with a
        // window on the canonical port. Anyone debugging "why is it
        // re-downloading the client" should find this line rather than guess.
        crate::commands::dlog(&format!(
            "bridge: PORT {PORT_BASE} was taken, running on {port}. This is a \
             DIFFERENT ORIGIN: the other instance's cached client and stored \
             settings are not visible here."
        ));
    }
    let shared = Arc::new(Mutex::new(base.clone()));
    let ship = shared.clone();
    std::thread::spawn(move || {
        for conn in listener.incoming().flatten() {
            let ship = ship.lock().unwrap().clone();
            std::thread::spawn(move || {
                let _ = serve(conn, &ship);
            });
        }
    });
    *guard = Some((shared, port));
    prewarm(&base);
    Ok(format!("http://127.0.0.1:{port}"))
}

/// The one owner-gated route that also answers the question the page wants:
/// which ship is this. auspex has no unauthenticated surface at all, so a 200
/// here means the session is real.
const WHOAMI: &str = "/apps/auspex/api/whoami";

/// Is the stored session actually good for `base`, and whose is it?
///
/// `Ok(Some(ship))` is logged in; `Ok(None)` is a live ship that does not know
/// us; `Err` is a ship we could not reach at all. Nothing cheaper is honest.
/// The cookie FILE existing says only that we logged in once, which is exactly
/// the state a connection page misreports as "connected". Doubles as a
/// connection warm-up, and saves the second request lattice makes to name the
/// ship — /api/whoami answers both questions at once.
pub fn probe(base: &str) -> Result<Option<String>, String> {
    let url = format!("{base}{WHOAMI}");
    // NOT the shared agent: that one deliberately has no read timeout (the
    // SSE beacon holds a connection open for hours), which for this one call
    // would let a wedged pier hold the connection page's status check open
    // indefinitely. A status check that cannot say "slow" inside ten seconds
    // should say "unreachable"; the page offers reconnect either way.
    let a = ureq::AgentBuilder::new()
        .redirects(0)
        .timeout(std::time::Duration::from_secs(10))
        .build();
    let req = with_cookie(a.get(&url));
    match req.call() {
        Ok(r) if r.status() == 200 => {
            let body = r.into_string().unwrap_or_default();
            // a 200 with an unreadable body is still a live session; the ship
            // name is a nicety and its absence must not read as logged out
            Ok(Some(ship_from_whoami(&body).unwrap_or_default()))
        }
        Ok(_) => Ok(None),
        // a 403/redirect is a live ship that does not know us: not connected,
        // but not an error either. Only a transport failure is an error.
        Err(ureq::Error::Status(_, _)) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// `{"ship":"~wex"}` — the whole of /api/whoami.
fn ship_from_whoami(body: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(body)
        .ok()?
        .get("ship")?
        .as_str()
        .filter(|s| is_patp(s))
        .map(str::to_string)
}

/// Shaped like an @p: a `~`, then lowercase letters and dashes, 57
/// characters at most (a comet). The connection page shows this name, so
/// whatever the ship or its cookie says is checked before it gets there.
fn is_patp(s: &str) -> bool {
    s.len() <= 57
        && s.strip_prefix('~')
            .is_some_and(|r| !r.is_empty() && r.bytes().all(|b| b.is_ascii_lowercase() || b == b'-'))
}

/// Post the +code to the ship's own login form and keep the session it hands
/// back. This is the one place a credential is used, and it is used once: the
/// +code is never stored, only the cookie it buys.
///
/// Returns `(cookie, ship)`. The @p comes out of the cookie's own NAME
/// (`urbauth-~wex`), so no second request is needed to learn it, and a cookie
/// whose name is not shaped like that is not a session however the ship
/// labelled the response.
pub fn login(base: &str, code: &str) -> Result<(String, String), String> {
    let url = format!("{base}/~/login");
    let resp = match agent().post(&url).send_form(&[("password", code)]) {
        Ok(r) => r,
        // eyre answers a wrong +code with a 4xx. That is the failure people
        // actually hit, and "the ship refused the +code" is the only useful
        // thing to say about it — a bare status number sends them looking for
        // a network problem they do not have.
        Err(ureq::Error::Status(s, _)) => {
            return Err(if (400..500).contains(&s) {
                format!("the ship refused the +code (HTTP {s}). Run |code in the dojo for a fresh one.")
            } else {
                format!("the ship answered HTTP {s} to the login")
            })
        }
        Err(e) => return Err(format!("could not reach {base}: {e}")),
    };
    let raw = resp
        .header("set-cookie")
        // A 200 with no cookie on it is the shape a reverse proxy that strips
        // set-cookie produces, and it would otherwise look like a successful
        // login followed by a workspace that 403s on everything.
        .ok_or("the ship accepted the login but set no session cookie")?;
    let cookie = cookie_from_set_cookie(raw)
        .ok_or_else(|| format!("the login returned a cookie we do not understand: {raw}"))?;
    let ship = ship_from_cookie(&cookie)
        .ok_or_else(|| format!("the session cookie names no ship: {cookie}"))?;
    Ok((cookie, ship))
}

/// The `name=value` out of a Set-Cookie header, attributes dropped.
///
/// Only an `urbauth-` cookie counts. Eyre sets exactly one and everything
/// downstream assumes the header we send is a session; taking whatever came
/// first would happily store a load balancer's affinity cookie and then
/// report a mystery 403 on every request.
pub fn cookie_from_set_cookie(raw: &str) -> Option<String> {
    let pair = raw.split(';').next()?.trim();
    let (name, value) = pair.split_once('=')?;
    if !name.starts_with("urbauth-") || value.is_empty() {
        return None;
    }
    Some(pair.to_string())
}

/// `urbauth-~wex=0v5.938s9…` -> `~wex`.
pub fn ship_from_cookie(cookie: &str) -> Option<String> {
    let name = cookie.split('=').next()?;
    let ship = name.strip_prefix("urbauth-")?;
    is_patp(ship).then(|| ship.to_string())
}

/// Write the session where every outbound request reads it from.
///
/// The cookie IS the ship login. 0600 on the file and 0700 on its directory,
/// set at creation rather than after the write, so there is no window where
/// another local user can read it. A plain `fs::write` under a default umask
/// lands 0644, which is how the first build shipped it.
pub fn store_cookie(path: &std::path::Path, cookie: &str) -> Result<(), String> {
    use std::io::Write as _;
    if let Some(dir) = path.parent() {
        let mut b = std::fs::DirBuilder::new();
        b.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt as _;
            b.mode(0o700);
        }
        b.create(dir).map_err(|e| e.to_string())?;
        #[cfg(unix)]
        {
            //  DirBuilder's mode applies only to a directory it creates. A
            //  directory a pre-fix build made is 0755 and stays so unless
            //  it is set every time, so it is set every time. Best effort:
            //  in production the parent is the app's own config dir, but a
            //  parent we do not own (the tests write under /tmp) refuses
            //  with EPERM, and that must not fail the login. The FILE mode
            //  below is the guarantee; the directory mode is defence in depth.
            use std::os::unix::fs::PermissionsExt as _;
            let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
        }
    }
    let mut o = std::fs::OpenOptions::new();
    o.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        o.mode(0o600);
    }
    let mut f = o.open(path).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        //  an existing 0644 file keeps its mode through OpenOptions; fix it
        use std::os::unix::fs::PermissionsExt as _;
        f.set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|e| e.to_string())?;
    }
    f.write_all(cookie.as_bytes()).map_err(|e| e.to_string())
}

/// The session cookie at `path`, if there is one. A file that is missing,
/// unreadable or blank is NOT a session: attaching an empty cookie header
/// would be a request we already know the ship will refuse.
pub fn session_cookie(path: &str) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|c| c.trim().to_string())
        .filter(|c| !c.is_empty())
}

/// The one place credentials go onto an outbound request. Read fresh every
/// time: a reconnect rewrites the cookie file, and the next request must use
/// the new session rather than one cached at startup.
pub fn with_cookie(req: ureq::Request) -> ureq::Request {
    match session_cookie(&crate::config::cookie_file()) {
        Some(c) => req.set("cookie", &c),
        None => req,
    }
}

/// pre-warm one ship connection so the first paint doesn't pay the TCP+TLS
/// handshake on top of the pier round-trip
fn prewarm(base: &str) {
    let warm = format!("{base}/apps/auspex/icon.svg");
    std::thread::spawn(move || {
        let _ = agent().get(&warm).call();
    });
}

/// one shared agent: its pool keeps ship connections (and TLS sessions) alive
/// across requests. A per-request agent paid a fresh TCP+TLS handshake to the
/// ship for every asset, which dominated remote loads. Several idle
/// connections per host, because a page load fetches in parallel and the SSE
/// beacon permanently occupies one — the notifier holds a second.
pub fn agent() -> &'static ureq::Agent {
    static A: std::sync::OnceLock<ureq::Agent> = std::sync::OnceLock::new();
    A.get_or_init(|| {
        ureq::AgentBuilder::new()
            .redirects(0)
            .max_idle_connections_per_host(6)
            // CONNECT timeout only, never read/write: the beacon holds a
            // connection open for hours and a read timeout would sever it on
            // every idle stretch — which for the notifier means a reconnect
            // storm instead of a stream. Connect is where an unreachable ship
            // hangs (SYN into the void), and 10s bounds it so the webview gets
            // its 502 while the client's own AbortController is still waiting.
            .timeout_connect(std::time::Duration::from_secs(10))
            .build()
    })
}

/// Headers the webview sent that must NOT be relayed on.
///
/// `cookie` is the load-bearing one. The whole point of the bridge is that the
/// webview holds no session and we attach ours Rust-side, so forwarding a page
/// cookie would put webkit's cookie behaviour back in the auth path. The rest
/// are hop-by-hop (they describe the webview↔bridge connection, not the
/// bridge↔ship one) plus `content-length`, which ureq recomputes.
///
/// NB: accept-encoding is deliberately NOT dropped. It rides through so the
/// ship can gzip and the webview decodes, which matters on every WAN load.
///
/// `origin` goes too. Every relayed request carries the bridge token, so the
/// bridge has already told its own webview from any other page. The ship's
/// cross-site gate compares Origin with Host, and Host is the ship's own by
/// the time the request arrives, so `http://127.0.0.1:26600` would read as
/// another site and refuse every write the workspace makes.
fn drop_request_header(lower_name: &str) -> bool {
    matches!(
        lower_name,
        "host" | "connection" | "cookie" | "content-length" | "origin"
            | "upgrade" | "keep-alive" | "proxy-connection" | "transfer-encoding"
    )
}

/// The cookie that carries this launch's bridge token.
const TOKEN_COOKIE: &str = "auspex-bridge";
/// Where the workspace's first navigation lands to pick up the token.
const BOOT_PATH: &str = "/.auspex-bridge/start";

/// This launch's bridge token: 32 bytes from the OS, hex. Made once, never
/// written to disk, gone when the app exits. getrandom rather than a read of
/// /dev/urandom, which does not exist on Windows.
pub fn token() -> &'static str {
    static T: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    T.get_or_init(|| {
        let mut b = [0u8; 32];
        getrandom::fill(&mut b).expect("no OS randomness for the bridge token");
        b.iter().map(|x| format!("{x:02x}")).collect()
    })
}

/// The url the workspace opens first: the bridge sets the token cookie and
/// redirects to `to`, a path on the bridge. Only open_workspace calls it.
/// It carries the token, so it is never logged.
pub fn bootstrap_url(local: &str, to: &str) -> String {
    format!("{local}{BOOT_PATH}?k={}&to={to}", token())
}

/// Compare without stopping at the first difference.
fn same_secret(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// Does this Cookie header carry this launch's token?
fn has_token(cookie: Option<&str>) -> bool {
    cookie.is_some_and(|c| {
        c.split(';').any(|kv| {
            kv.trim()
                .strip_prefix(TOKEN_COOKIE)
                .and_then(|v| v.strip_prefix('='))
                .is_some_and(|v| same_secret(v.as_bytes(), token().as_bytes()))
        })
    })
}

/// A redirect target the bootstrap will accept: a plain path on the bridge.
fn plain_path(to: &str) -> bool {
    to.starts_with('/')
        && !to.starts_with("//")
        && to.bytes().all(|b| b.is_ascii_alphanumeric() || b"/_.-".contains(&b))
}

/// One request off the wire, already filtered, ready to relay. An empty body
/// means the request had none: that is what decides send_bytes vs call.
struct Incoming {
    method: String,
    target: String,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

/// What to do with one request off the wire.
enum Request {
    /// relay it to the ship, with the session
    Relay(Incoming),
    /// the workspace's first navigation: set the token cookie, go here
    Bootstrap(String),
    /// answer with this status line and never contact the ship
    Refuse(&'static str),
    /// say nothing: no request line, or a body cut short
    Drop,
}

/// Read one request. Drop is a request we will not serve at all: no request
/// line, or a body that stopped short of what its Content-Length promised.
/// Refuse is one without this launch's token, answered before its body is
/// read and never relayed.
///
/// Split from serve so the interesting inputs (a lying Content-Length, a
/// truncated body, a header line with no colon) can be fed in as bytes.
fn read_request(reader: &mut impl BufRead) -> std::io::Result<Request> {
    let mut line = String::new();
    reader.read_line(&mut line)?;
    let mut parts = line.split_whitespace();
    let (method, target) = match (parts.next(), parts.next()) {
        (Some(m), Some(t)) => (m.to_string(), t.to_string()),
        _ => return Ok(Request::Drop),
    };
    // Origin-form only. The upstream URL is `ship + target`, so a target
    // that does not start with '/' (an absolute URI, or `@evil.com/x`,
    // which url-parses as a userinfo and a DIFFERENT host) would carry the
    // session cookie somewhere other than the configured ship. No browser
    // emits such a target to a same-origin server; a raw local client can.
    if !target.starts_with('/') {
        return Ok(Request::Drop);
    }
    // headers: keep what the page sent except hop-by-hop, host and cookies.
    // Accept-Encoding passes THROUGH. ureq (no gzip feature) hands us the
    // compressed body verbatim and Content-Encoding rides back with it, so
    // the webview decodes. Stripping it made every WAN transfer identity,
    // which is a real tax on app.js vs a plain browser.
    let mut headers: Vec<(String, String)> = Vec::new();
    let mut content_len = 0usize;
    // cookie is never relayed, but the bridge token rides in it
    let mut cookie = None;
    loop {
        let mut h = String::new();
        reader.read_line(&mut h)?;
        let h = h.trim_end();
        if h.is_empty() {
            break;
        }
        let Some((k, v)) = h.split_once(':') else { continue };
        let (k, v) = (k.trim(), v.trim());
        let kl = k.to_ascii_lowercase();
        if kl == "content-length" {
            content_len = v.parse().unwrap_or(0);
        }
        if kl == "cookie" {
            cookie = Some(v.to_string());
        }
        if drop_request_header(&kl) {
            continue;
        }
        headers.push((k.to_string(), v.to_string()));
    }
    // the first navigation has no cookie yet. The token in its query is
    // the proof, and it is only ever turned into the cookie, never relayed.
    if let Some(q) = target.strip_prefix(BOOT_PATH).and_then(|r| r.strip_prefix('?')) {
        let arg = |name: &str| {
            q.split('&').find_map(|kv| kv.strip_prefix(name).and_then(|v| v.strip_prefix('=')))
        };
        return Ok(match (arg("k"), arg("to")) {
            (Some(k), Some(to)) if method == "GET"
                && same_secret(k.as_bytes(), token().as_bytes())
                && plain_path(to) => Request::Bootstrap(to.to_string()),
            _ => Request::Refuse("403 Forbidden"),
        });
    }
    if !has_token(cookie.as_deref()) {
        return Ok(Request::Refuse("403 Forbidden"));
    }
    // allocate as bytes actually arrive, never what the header claims: a
    // request lying "Content-Length: 10^18" was an instant OOM abort via
    // vec![0; huge] before a single body byte existed.
    let mut body = Vec::new();
    if content_len > 0 {
        (&mut *reader).take(content_len as u64).read_to_end(&mut body)?;
        if body.len() < content_len {
            return Ok(Request::Drop); // truncated body: same as a failed read_exact
        }
    }
    Ok(Request::Relay(Incoming { method, target, headers, body }))
}

/// Answer `status` with no ship involved, then close. The client may still
/// be sending a request we never read. Closing on unread bytes makes the
/// kernel send a reset, which can eat the reply, so half-close and drain a
/// bounded amount first.
fn refuse(mut c: TcpStream, reader: &mut impl Read, status: &str) -> std::io::Result<()> {
    write!(
        c,
        "HTTP/1.1 {status}\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{status}",
        status.len()
    )?;
    c.shutdown(std::net::Shutdown::Write).ok();
    c.set_read_timeout(Some(std::time::Duration::from_secs(2))).ok();
    let _ = std::io::copy(&mut reader.take(1 << 20), &mut std::io::sink());
    Ok(())
}

/// Status line, filtered headers, then the body as it arrives.
fn relay_response(c: &mut TcpStream, resp: ureq::Response) -> std::io::Result<()> {
    write!(c, "HTTP/1.1 {} {}\r\n", resp.status(), resp.status_text())?;
    for name in resp.headers_names() {
        let nl = name.to_ascii_lowercase();
        // close-delimited relay: length/framing headers are ours to own.
        // set-cookie is dropped on purpose. The webview must stay cookieless.
        if matches!(
            nl.as_str(),
            "content-length" | "transfer-encoding" | "connection" | "set-cookie" | "keep-alive"
        ) {
            continue;
        }
        if let Some(v) = resp.header(&name) {
            write!(c, "{name}: {v}\r\n")?;
        }
    }
    write!(c, "Connection: close\r\n\r\n")?;
    // streamed: each read is written as it lands, so SSE events arrive as
    // they happen (a TcpStream has no buffer to flush). A peer that goes
    // away mid-body ends the relay, which is all there is to do about it.
    let _ = std::io::copy(&mut resp.into_reader(), c);
    Ok(())
}

fn serve(client: TcpStream, ship: &str) -> std::io::Result<()> {
    client.set_nodelay(true).ok();
    let mut reader = BufReader::new(client.try_clone()?);
    let req = match read_request(&mut reader)? {
        Request::Relay(req) => req,
        Request::Refuse(status) => {
            crate::commands::dlog(&format!("bridge: refused {status}"));
            return refuse(client, &mut reader, status);
        }
        Request::Drop => return Ok(()),
        Request::Bootstrap(to) => {
            crate::commands::dlog("bridge: workspace token handed over");
            let mut c = client;
            return write!(
                c,
                "HTTP/1.1 302 Found\r\nLocation: {to}\r\n\
                 Set-Cookie: {TOKEN_COOKIE}={}; Path=/; HttpOnly; SameSite=Strict\r\n\
                 Cache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                token()
            );
        }
    };
    crate::commands::dlog(&format!("bridge: {} {}", req.method, req.target));

    let mut out = agent().request(&req.method, &format!("{ship}{}", req.target));
    for (k, v) in &req.headers {
        out = out.set(k, v);
    }
    let out = with_cookie(out);
    let resp = if !req.body.is_empty() { out.send_bytes(&req.body) } else { out.call() };
    let mut c = client;
    let resp = match resp {
        Ok(r) => r,
        Err(ureq::Error::Status(_, r)) => r,
        Err(e) => {
            let msg = format!("bridge: ship unreachable: {e}");
            write!(
                c,
                "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{}",
                msg.len(),
                msg
            )?;
            return Ok(());
        }
    };

    relay_response(&mut c, resp)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_webviews_cookie_is_never_relayed() {
        // the bridge exists so the webview holds NO session. Forwarding its
        // cookie would put webkit's cookie behaviour back in the auth path,
        // which is the entire class of bug this design removed.
        assert!(drop_request_header("cookie"));
        // hop-by-hop headers describe the webview<->bridge hop, not ours
        for h in ["host", "connection", "content-length", "upgrade",
                  "keep-alive", "proxy-connection", "transfer-encoding"] {
            assert!(drop_request_header(h), "{h} must not be relayed");
        }
        // the bridge's own origin is not the ship's, and the ship's
        // cross-site gate would refuse every write that carried it
        assert!(drop_request_header("origin"));
        // accept-encoding MUST ride through. The ship gzips and the webview
        // decodes. Dropping it made every WAN transfer identity-encoded.
        assert!(!drop_request_header("accept-encoding"));
        for h in ["accept", "user-agent", "referer", "if-none-match", "range"] {
            assert!(!drop_request_header(h), "{h} should reach the ship");
        }
    }

    use crate::testutil::Stub;
    use proptest::prelude::*;

    #[test]
    fn only_an_origin_form_target_is_relayed() {
        // `ship + target` is the upstream URL. A target that does not start
        // with '/' would carry the session cookie to a different host:
        // `@evil.com/x` url-parses as userinfo + host evil.com.
        let read = |req: String| read_request(&mut std::io::Cursor::new(req.into_bytes())).unwrap();
        let tok = token_cookie();
        for bad in ["@evil.com/x", "http://evil.com/"] {
            let req = read(format!("GET {bad} HTTP/1.1\r\n{tok}\r\n"));
            assert!(matches!(req, Request::Drop), "{bad:?} must be refused");
        }
        let req = read(format!("GET /apps/auspex/ HTTP/1.1\r\n{tok}\r\n"));
        assert!(matches!(req, Request::Relay(_)));
        // and without the token even a good target goes nowhere
        let req = read("GET /apps/auspex/ HTTP/1.1\r\n\r\n".to_string());
        assert!(matches!(req, Request::Refuse("403 Forbidden")));
    }

    /// The Cookie line the workspace sends once the bootstrap has run.
    fn token_cookie() -> String {
        format!("cookie: {TOKEN_COOKIE}={}\r\n", token())
    }

    #[test]
    fn only_this_launchs_token_counts() {
        // the token only counts by exact value, under its own name
        let tok = token();
        assert_eq!(tok.len(), 64, "256 bits, hex");
        assert_eq!(tok, token(), "one token per launch");
        assert!(has_token(Some(&format!("a=b; {TOKEN_COOKIE}={tok}"))));
        assert!(!has_token(Some(&format!("{TOKEN_COOKIE}={}", &tok[1..]))));
        assert!(!has_token(Some(&format!("{TOKEN_COOKIE}x={tok}"))));
        assert!(!has_token(Some(&format!("{TOKEN_COOKIE}={tok}0"))));
        assert!(!has_token(Some("")));
        assert!(!has_token(None));
    }

    #[test]
    fn a_request_without_the_token_never_reaches_the_ship() {
        // Any page in any browser can aim at 127.0.0.1, and so can another
        // account or a sandboxed app. Before the token, each of these was
        // relayed with the owner's session attached (security audit run-1).
        let ship = Stub::new(|_| (200, "relayed".to_string()));
        let host = format!("host: 127.0.0.1:{PORT_BASE}\r\n");
        for req in [
            // curl, or any other local process
            format!("GET /apps/auspex/api/whoami HTTP/1.1\r\n{host}\r\n"),
            // a cross-site form POST from a page in a browser
            format!(
                "POST /apps/auspex/api/send HTTP/1.1\r\n{host}origin: https://evil.example\r\n\
                 content-type: text/plain\r\ncontent-length: 2\r\n\r\nhi"
            ),
            // a token that is nearly right is not the token
            format!(
                "GET /apps/auspex/ HTTP/1.1\r\n{host}cookie: {TOKEN_COOKIE}={}\r\n\r\n",
                &token()[1..]
            ),
        ] {
            let back = String::from_utf8_lossy(&through_bridge(req.as_bytes(), &ship.base)).into_owned();
            assert!(back.starts_with("HTTP/1.1 403 Forbidden"), "{req}: {back}");
        }
        assert!(ship.requests().is_empty(), "a request without the token reached the ship");
    }

    #[test]
    fn the_bootstrap_hands_over_the_token_and_nothing_else() {
        let ship = Stub::new(|_| (200, "relayed".to_string()));
        let get = |target: &str| {
            String::from_utf8_lossy(&through_bridge(
                format!("GET {target} HTTP/1.1\r\nhost: 127.0.0.1:{PORT_BASE}\r\n\r\n").as_bytes(),
                &ship.base,
            ))
            .into_owned()
        };
        let ok = get(&bootstrap_url("", "/apps/auspex/"));
        assert!(ok.starts_with("HTTP/1.1 302 Found"), "{ok}");
        assert!(ok.contains("\r\nLocation: /apps/auspex/\r\n"), "{ok}");
        assert!(
            ok.contains(&format!("Set-Cookie: {TOKEN_COOKIE}={}; Path=/; HttpOnly; SameSite=Strict", token())),
            "{ok}"
        );
        // a wrong token, or a redirect off the bridge, gets nothing
        for bad in [
            format!("{BOOT_PATH}?k=00&to=/apps/auspex/"),
            format!("{BOOT_PATH}?to=/apps/auspex/"),
            format!("{BOOT_PATH}?k={}&to=//evil.example/", token()),
            format!("{BOOT_PATH}?k={}&to=https://evil.example/", token()),
            format!("{BOOT_PATH}?k={}&to=/a%0d%0aSet-Cookie:x", token()),
        ] {
            let back = get(&bad);
            assert!(back.starts_with("HTTP/1.1 403 Forbidden"), "{bad}: {back}");
            assert!(!back.contains("Set-Cookie"), "{bad}");
        }
        // only a GET, the navigation the workspace makes
        let post = String::from_utf8_lossy(&through_bridge(
            format!("POST {} HTTP/1.1\r\n\r\n", bootstrap_url("", "/apps/auspex/")).as_bytes(),
            &ship.base,
        ))
        .into_owned();
        assert!(post.starts_with("HTTP/1.1 403 Forbidden"), "{post}");
        // and the ship never saw any of it
        assert_eq!(ship.requests().len(), 0);
    }

    #[cfg(unix)]
    #[test]
    fn the_cookie_file_is_private() {
        use std::os::unix::fs::PermissionsExt as _;
        let dir = std::env::temp_dir().join(format!("auspex-cookie-{}", std::process::id()));
        let path = dir.join("cookie");
        // the directory pre-exists at 0755, as one made by a pre-fix build does
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        // twice: the second write hits the existing-file path, which keeps
        // whatever mode the file already has unless it is set explicitly
        for _ in 0..2 {
            store_cookie(&path, "urbauth-~wex=0v1").unwrap();
            let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600, "cookie file mode {mode:o}");
        }
        let dmode = std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(dmode, 0o700, "cookie dir mode {dmode:o}");
        std::fs::remove_dir_all(&dir).ok();
    }

    /// Point the cookie file at a per-process temp path holding `cookie`, or
    /// at nothing when None. The bridge and the probe both read
    /// config::cookie_file(), which in the app is set once at setup.
    fn with_session(cookie: Option<&str>) -> std::path::PathBuf {
        let p = std::env::temp_dir()
            .join(format!("auspex-test-cookie-{}", std::process::id()));
        match cookie {
            Some(c) => std::fs::write(&p, c).unwrap(),
            None => {
                std::fs::remove_file(&p).ok();
            }
        }
        crate::config::publish_cookie_path(&p);
        p
    }

    /// Push raw bytes through a real serve() relaying to `ship` and collect
    /// whatever the client gets back. serve() runs to completion before this
    /// returns, so "the ship saw nothing" is a decision, not a race.
    fn through_bridge(req: &[u8], ship: &str) -> Vec<u8> {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let addr = listener.local_addr().unwrap();
        let ship = ship.to_string();
        let t = std::thread::spawn(move || {
            let (conn, _) = listener.accept().unwrap();
            let _ = serve(conn, &ship);
        });
        let mut c = TcpStream::connect(addr).unwrap();
        c.write_all(req).ok();
        c.shutdown(std::net::Shutdown::Write).ok();
        let mut out = Vec::new();
        let _ = c.read_to_end(&mut out);
        t.join().expect("serve must not panic");
        out
    }

    /// Feed raw bytes to a real serve() with a dead upstream and collect
    /// whatever it answers. The property is survival: reply or drop, never
    /// panic (the join would surface it) and never abort on an absurd claim.
    fn poke_bridge(req: &[u8]) -> Vec<u8> {
        through_bridge(req, "http://127.0.0.1:1") // nothing listens: refused fast
    }

    /// one plain GET straight at the bridge's own port, returning the body
    fn get_through_bridge(base: &str, path: &str) -> String {
        let addr = base.trim_start_matches("http://").to_string();
        let mut c = TcpStream::connect(addr).unwrap();
        write!(c, "GET {path} HTTP/1.1\r\nhost: bridge\r\n{}\r\n", token_cookie()).unwrap();
        c.shutdown(std::net::Shutdown::Write).ok();
        let mut out = String::new();
        c.read_to_string(&mut out).unwrap();
        out.rsplit("\r\n\r\n").next().unwrap_or_default().to_string()
    }

    #[test]
    fn a_request_body_reaches_the_ship_byte_for_byte() {
        // Nothing else in this file proves a POST body is forwarded AT ALL.
        // If it silently stopped being, every send, every read-mark and every
        // attachment upload would arrive at the ship empty while the webview
        // saw a 200 — a mail client that reports sent and sends nothing.
        with_session(Some("urbauth-~wex=0v1.session"));
        let ship = Stub::new(|_| (200, "sent".to_string()));
        let body = r#"{"to":["~feb"],"subject":"hi","body":"bytes that must survive the hop","prev":null}"#;
        // the token rides in the webview's Cookie header beside whatever
        // else the page holds, and Origin is what the webview's fetch sends
        let req = format!(
            "POST /apps/auspex/api/send HTTP/1.1\r\nhost: 127.0.0.1:{PORT_BASE}\r\n\
             cookie: webview-junk=1; {TOKEN_COOKIE}={}\r\ncontent-length: {}\r\n\
             origin: http://127.0.0.1:{PORT_BASE}\r\n\
             x-auspex-probe: keep-me\r\naccept-encoding: gzip\r\n\r\n{body}",
            token(),
            body.len()
        );
        let back = through_bridge(req.as_bytes(), &ship.base);

        let seen = ship.only();
        assert_eq!(seen.method, "POST", "the method is relayed as sent");
        assert_eq!(seen.target, "/apps/auspex/api/send", "path AND query");
        assert_eq!(seen.body_str(), body, "the body must arrive intact");
        assert_eq!(seen.header("content-length"), Some(body.len().to_string().as_str()));
        // ordinary request headers ride through...
        assert_eq!(seen.header("x-auspex-probe"), Some("keep-me"));
        // ...including accept-encoding, or every WAN transfer goes identity
        assert_eq!(seen.header("accept-encoding"), Some("gzip"));
        // ...and OUR session is what authenticates it
        assert_eq!(seen.header("cookie"), Some("urbauth-~wex=0v1.session"));
        // ...but never the webview's own cookie: that is the whole design
        assert!(
            !seen.header_blob().contains("webview-junk"),
            "the webview's cookie was relayed: {}",
            seen.header_blob()
        );
        // ...nor the bridge token, which is the bridge's business only
        assert!(!seen.header_blob().contains(token()), "the bridge token was relayed");
        // ...nor the bridge's origin, which the ship would read as another site
        assert_eq!(seen.header("origin"), None);

        // and the ship's answer comes back, status line and body
        let back = String::from_utf8_lossy(&back);
        assert!(back.starts_with("HTTP/1.1 200 OK"), "{back}");
        assert!(back.ends_with("sent"), "the response body must reach the webview: {back}");
    }

    #[test]
    fn a_truncated_body_is_never_forwarded_as_a_short_one() {
        // a client that promises 64 bytes and dies after 4 must not have its
        // half-written message posted to the ship as a complete one
        let ship = Stub::new(|_| (200, "should not happen".to_string()));
        let back = through_bridge(
            format!("POST /apps/auspex/api/send HTTP/1.1\r\n{}content-length: 64\r\n\r\nhalf", token_cookie())
                .as_bytes(),
            &ship.base,
        );
        assert!(ship.requests().is_empty(), "a truncated body reached the ship");
        assert!(back.is_empty(), "the webview must get no fabricated reply");
    }

    #[test]
    fn an_unreachable_ship_is_a_502_and_not_a_hang() {
        // the client's own error handling depends on failure arriving FAST
        // and looking like a failure, not like an empty success
        let req = format!("GET /apps/auspex/app.js HTTP/1.1\r\n{}\r\n", token_cookie());
        let back = String::from_utf8_lossy(&poke_bridge(req.as_bytes())).into_owned();
        assert!(back.starts_with("HTTP/1.1 502 Bad Gateway"), "{back}");
    }

    #[test]
    fn probe_reports_the_session_honestly() {
        // 200 on the owner-gated route is the ONLY thing that means logged
        // in. The connection page reads this directly, so a wrong answer
        // either strands the user on a login form or claims a ship it cannot
        // reach.
        with_session(Some("urbauth-~wex=0v1.session"));
        let live = Stub::new(|_| (200, r#"{"ship":"~wex"}"#.to_string()));
        assert_eq!(probe(&live.base), Ok(Some("~wex".to_string())));
        assert_eq!(
            live.only().target,
            WHOAMI,
            "the probe must hit the owner-gated route, not something public"
        );
        // a live ship that does not know us: not connected, but not an error
        let stale = Stub::new(|_| (403, "forbidden".to_string()));
        assert_eq!(probe(&stale.base), Ok(None));
        // a ship that answers something other than 200 is not a session either
        let odd = Stub::new(|_| (307, String::new()));
        assert_eq!(probe(&odd.base), Ok(None));
        // a 200 whose body we cannot read is STILL a live session: the ship
        // name is a nicety, and losing it must not read as logged out
        let mute = Stub::new(|_| (200, "not json".to_string()));
        assert_eq!(probe(&mute.base), Ok(Some(String::new())));
        // nothing listening is an error, which the page must advise on
        // differently from "reachable but logged out"
        assert!(probe("http://127.0.0.1:1").is_err());
        // (a trailing slash in the config is config::load_at's to trim)
    }

    #[test]
    fn login_posts_the_code_and_keeps_only_the_cookie() {
        // The whole connect flow. This replaced lattice-fs's login, so
        // nothing else in the tree proves the +code goes to the right route
        // in the right encoding, or that the session that comes back is what
        // gets stored.
        let ship = Stub::headed(|_| {
            (
                200,
                vec![(
                    "set-cookie".to_string(),
                    "urbauth-~wex=0v5.938s9.4kpjq; Path=/; Max-Age=2592000".to_string(),
                )],
                "0v5.938s9.4kpjq".to_string(),
            )
        });
        let (cookie, who) = login(&ship.base, "novwel-tamfes-daplex-misdem").unwrap();
        let seen = ship.only();
        assert_eq!(seen.method, "POST");
        assert_eq!(seen.target, "/~/login");
        assert_eq!(
            seen.body_str(),
            "password=novwel-tamfes-daplex-misdem",
            "eyre's login form takes `password`, urlencoded"
        );
        assert_eq!(
            cookie, "urbauth-~wex=0v5.938s9.4kpjq",
            "the attributes are the browser's business, not ours"
        );
        assert_eq!(who, "~wex", "the @p comes out of the cookie's own name");

        // A 200 with no set-cookie is what a reverse proxy that strips them
        // produces. Without this it looks like a successful login followed by
        // a workspace that 403s on everything.
        let stripped = Stub::new(|_| (200, "ok".to_string()));
        let e = login(&stripped.base, "x").unwrap_err();
        assert!(e.contains("no session cookie"), "{e}");

        // a wrong +code must say so, not report a network problem
        let refused = Stub::new(|_| (400, "bad".to_string()));
        let e = login(&refused.base, "wrong").unwrap_err();
        assert!(e.contains("refused the +code"), "{e}");

        // an unreachable ship is a different sentence again
        let e = login("http://127.0.0.1:1", "x").unwrap_err();
        assert!(e.contains("could not reach"), "{e}");
    }

    #[test]
    fn only_an_urbauth_cookie_is_a_session() {
        assert_eq!(
            cookie_from_set_cookie("urbauth-~wex=0v1.2ab3c; Path=/; Max-Age=2592000").as_deref(),
            Some("urbauth-~wex=0v1.2ab3c")
        );
        // a load balancer's affinity cookie is not a session, and storing it
        // buys a mystery 403 on every later request
        assert_eq!(cookie_from_set_cookie("AWSALB=abc; Path=/"), None);
        assert_eq!(cookie_from_set_cookie("urbauth-~wex=; Path=/"), None);
        assert_eq!(cookie_from_set_cookie("nonsense"), None);

        assert_eq!(ship_from_cookie("urbauth-~wex=0v1.2ab3c").as_deref(), Some("~wex"));
        assert_eq!(
            ship_from_cookie("urbauth-~mister-botter-dozzod-nisfeb=0v1.2").as_deref(),
            Some("~mister-botter-dozzod-nisfeb")
        );
        assert_eq!(ship_from_cookie("urbauth-=0v1.2"), None, "a nameless ship is not one");
        assert_eq!(ship_from_cookie("session=0v1.2"), None);
        // the name reaches the connection page, so markup is not a name
        assert_eq!(ship_from_cookie("urbauth-~<img src=x onerror=alert(1)>=0v1"), None);
    }

    #[test]
    fn whoami_names_a_ship_or_nothing() {
        // The connection page wrote this name as HTML. A ship (or whatever
        // answers at its URL) could run script in the manager page, which
        // holds every shell command (security audit run-1).
        let hostile = r#"{"ship":"<img src=x onerror=\"window.__TAURI__.core.invoke('set_theme',{dark:true})\">"}"#;
        assert_eq!(ship_from_whoami(hostile), None);
        assert_eq!(ship_from_whoami(r#"{"ship":"~sampel-palnet"}"#).as_deref(), Some("~sampel-palnet"));
        // a comet is the longest @p there is, and one more character is not one
        let comet = "~dozzod-dozzod-dozzod-dozzod--dozzod-dozzod-dozzod-dozzod";
        assert_eq!(comet.len(), 57);
        assert!(is_patp(comet));
        assert!(!is_patp(&format!("{comet}a")));
        for bad in ["", "~", "zod", "~Zod", "~zod ", "~zod\n", "~zød"] {
            assert!(!is_patp(bad), "{bad:?}");
        }
    }

    #[test]
    fn the_session_cookie_is_attached_only_when_there_is_one() {
        // every authenticated request the shell makes goes through here. If it
        // stopped attaching, the whole workspace would 403 with the cookie
        // file sitting right there; if it attached a blank one, likewise.
        let p = std::env::temp_dir().join(format!("auspex-ck-{}", std::process::id()));
        std::fs::remove_file(&p).ok();
        let path = p.to_string_lossy().into_owned();
        assert_eq!(session_cookie(&path), None, "no file is no session");
        std::fs::write(&p, b"  \n ").unwrap();
        assert_eq!(session_cookie(&path), None, "a blank file is no session");
        store_cookie(&p, "urbauth-~wex=0v1.2ab3c").unwrap();
        assert_eq!(
            session_cookie(&path).as_deref(),
            Some("urbauth-~wex=0v1.2ab3c"),
            "the cookie is passed on verbatim"
        );
        std::fs::remove_file(&p).ok();
        // store_cookie makes the config dir on the way: a first connect on a
        // fresh machine has no <app_config_dir> yet
        let nested = std::env::temp_dir()
            .join(format!("auspex-ck-dir-{}", std::process::id()))
            .join("cookie");
        std::fs::remove_dir_all(nested.parent().unwrap()).ok();
        store_cookie(&nested, "urbauth-~wex=0v1.2").unwrap();
        assert_eq!(
            session_cookie(&nested.to_string_lossy()).as_deref(),
            Some("urbauth-~wex=0v1.2")
        );
        std::fs::remove_dir_all(nested.parent().unwrap()).ok();
    }

    proptest! {
        // few cases: each one is a real TCP round-trip
        #![proptest_config(ProptestConfig { cases: 24, ..ProptestConfig::default() })]

        // a local client can write ANYTHING at the bridge socket
        #[test]
        fn serve_survives_arbitrary_request_bytes(
            req in proptest::collection::vec(any::<u8>(), 0..256),
        ) {
            poke_bridge(&req);
        }

        // a lying content-length must not allocate what the header claims:
        // "Content-Length: 10^18" with no body was an instant OOM abort
        #[test]
        fn a_lying_content_length_cannot_oom(len in any::<u64>()) {
            // with the token, or the 403 would answer before the length is read
            let req = format!("POST /x HTTP/1.1\r\n{}content-length: {len}\r\n\r\nhi", token_cookie());
            poke_bridge(req.as_bytes());
        }

        // whatever a ship (or something in front of it) puts in a Set-Cookie,
        // the answer is either None or a name=value that really is a session
        #[test]
        fn cookie_parsing_is_total(raw in ".{0,64}") {
            if let Some(c) = cookie_from_set_cookie(&raw) {
                prop_assert!(c.starts_with("urbauth-"));
                prop_assert!(!c.contains(';'));
                prop_assert!(c.contains('='));
            }
        }
    }

    /// Wait for exclusive use of the bridge port range. What can hold a port
    /// in it is another test process, several of which run at once under
    /// cargo-mutants. The kernel is no longer a contender: PORT_BASE sits
    /// below the ephemeral floor (32768), so no outgoing connection can be
    /// handed one of these ports.
    ///
    /// So: take a port outside the asserted range as a cross-process lock (no
    /// dependency, no cleanup), then wait for the range itself to be clear.
    /// The lock is deliberately never released. ensure() hands PORT_BASE to a
    /// thread that owns it for the life of the process, so a claim ending with
    /// the test would let the next process in while this one still held it.
    fn claim_the_port_range() {
        // generous: the claim is held for a whole process lifetime, so N
        // concurrent test binaries serialize on it
        for _ in 0..600 {
            if let Ok(lock) = TcpListener::bind(("127.0.0.1", PORT_BASE + PORT_SPAN + 1)) {
                if (0..2).all(|i| TcpListener::bind(("127.0.0.1", PORT_BASE + i)).is_ok()) {
                    std::mem::forget(lock);
                    return;
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        panic!(
            "127.0.0.1:{PORT_BASE}..{} never came free. Something holds one of \
             those ports: the desktop app itself, or another test binary.",
            PORT_BASE + 2
        );
    }

    /// One test, because ensure() hands its listener to a thread that owns it
    /// for the life of the process: nothing can free PORT_BASE again, so the
    /// bind-stable assertions have to run first, in the same test.
    #[test]
    fn the_bridge_port_is_deterministic_and_relays_to_the_current_ship() {
        claim_the_port_range();
        // The port is part of the webview's ORIGIN, and web storage is keyed
        // by origin. A moving port gives every launch an empty service-worker
        // cache, which is what made lattice's desktop app slower than the same
        // UI in a browser. So the first bind must be PORT_BASE, and a taken
        // port must step by one rather than fall back to an ephemeral one.
        let (first, p1) = bind_stable().expect("a free port in the range");
        assert_eq!(p1, PORT_BASE, "first bind must be the deterministic port");
        let (second, p2) = bind_stable().expect("the range has room");
        assert_eq!(p2, PORT_BASE + 1, "a taken port steps by one, stays stable");
        drop(first);
        drop(second);
        // and with the range free again we are back to the same origin
        let (third, p3) = bind_stable().expect("free again");
        assert_eq!(p3, PORT_BASE, "the origin is recoverable, not drifting");
        drop(third);

        // Quit the app, rebuild, launch again. The previous instance is still
        // letting go of its listener, so a bind that gives up immediately
        // lands on PORT_BASE+1 — a DIFFERENT ORIGIN with an empty cache.
        let (held, hp) = bind_stable().expect("free range");
        assert_eq!(hp, PORT_BASE);
        let releaser = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(400));
            drop(held); // the outgoing instance finally exits
        });
        let (got, port) = bind_stable().expect("the canonical port comes free");
        assert_eq!(
            port, PORT_BASE,
            "a relaunch must wait for the SAME origin rather than silently \
             taking a new one"
        );
        drop(got);
        releaser.join().unwrap();

        // And the bridge that port belongs to must actually forward. ensure()
        // returning a plausible-looking url without a live listener behind it
        // is a blank window; forwarding to a stale ship after a re-point is
        // one ship's mail served under another ship's session and origin.
        let ship1 = Stub::new(|_| (200, "ship one".to_string()));
        let ship2 = Stub::new(|_| (200, "ship two".to_string()));
        let bridge = Bridge(Mutex::new(None));

        let local = ensure(&bridge, &ship1.base).expect("bridge starts");
        assert_eq!(local, format!("http://127.0.0.1:{PORT_BASE}"), "the webview's origin");
        assert_eq!(get_through_bridge(&local, "/apps/auspex/"), "ship one");
        assert!(ship1.asked_for("/apps/auspex/"), "{:?}", ship1.requests().len());

        let again = ensure(&bridge, &ship2.base).expect("re-point");
        assert_eq!(again, local, "a ship change must NOT move the origin");
        assert_eq!(
            get_through_bridge(&local, "/apps/auspex/"),
            "ship two",
            "the bridge kept relaying to the previous ship after a re-point"
        );
    }
}
