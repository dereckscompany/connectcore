# StreamClient: Event-Driven WebSocket Base for Connectors

StreamClient: Event-Driven WebSocket Base for Connectors

StreamClient: Event-Driven WebSocket Base for Connectors

## Details

A Node.js-style event-driven base for long-lived WebSocket streams (any
long-lived push feed). You register handlers with `$on(event, handler)`
— exactly like `ws.on("message", ...)` in JavaScript — and the library
calls them as messages arrive on R's event loop (the `later` package,
which, like Node, is built on libuv). Concrete connectors subclass it
and override two seams — `.dispatch()` (how a raw frame becomes events)
and `.resubscribe()` (what to re-send after a (re)connect) — getting all
of the reconnect / keepalive / watchdog machinery for free.

### Why no `async` flag (unlike a REST client)

A REST call has a single result, so it can return a value (sync) or a
promise (async). A socket is an endless push stream with no single
result, so the only sensible shape is a callback. Streams are therefore
always event-driven; the one thing R needs that Node gives for free is a
way to keep the process alive and pump the loop — that is `$run()`.

### Events

The set is **open** — `$on(event, ...)` accepts any string, and a
subclass' `.dispatch()` may `emit` its own (e.g. one event per message
type). The base emits a standard core:

- `"open"` — the socket connected (payload: the open event).

- `"message"` — the default `.dispatch()` emits this for every frame,
  carrying the message as a **character string** (binary frames are
  decoded with
  [`rawToChar()`](https://rdrr.io/r/base/rawConversion.html) first, so a
  handler always gets text).

- `"close"` / `"error"` — the socket closed / errored (payload: the
  event).

- `"reconnecting"` — about to retry (payload: `list(attempt, delay)`).

- `"reconnected"` — a reconnect (not the first connect) succeeded.

- `"giveup"` — `max_reconnects` exhausted; the `$run()` loop will exit.

- `"stale"` — the silence watchdog fired (no frame within
  `stale_timeout`).

### Typed lifecycle events (`$on_event()`)

Alongside the string-keyed `$on()` callbacks above, `$on_event(handler)`
delivers a single **typed** object (see
[ws_event](https://dereckscompany.github.io/connectcore/reference/ws_event.md))
for every lifecycle transition — `open`, `message`, `close`, `error`,
`reconnect` (see
[WS_EVENT_TYPES](https://dereckscompany.github.io/connectcore/reference/WS_EVENT_TYPES.md))
— each with a lubridate UTC `timestamp` and per-type fields (`close`
carries `code` + `reason`; `reconnect` carries `attempt` + `delay`;
`open` carries `reconnect`; `message` carries `data`; `error` carries
`error`). This is the WebSocket analogue of the typed REST conditions
([`?connectcore_conditions`](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)):
branch on `event$event_type` and read fields as data instead of
re-parsing a raw callback payload. It is **additive** — the `$on()`
callbacks are unchanged — and the typed object is materialised only when
an `$on_event()` handler is registered, so the parse-free hot path stays
free by default.

### Connection management (handled for you)

- **Auto-reconnect** with full-jitter exponential backoff, so a
  reconnect storm cannot trip a connection rate limit.

- **Silence watchdog** — if `stale_timeout` is set and no frame arrives
  within it, the socket is force-closed and reopened (a dead connection
  that never fired `onClose`).

- **Proactive reconnect** — if `proactive_reconnect` is set, reconnect
  that many seconds after opening (e.g. to beat a server's 24-hour
  forced cutoff).

- **Re-subscribe** after every (re)connect via the `.resubscribe()`
  hook.

- **Keepalive** keeps one task on the `later` queue so a host-driven
  `while (!later::loop_empty())` loop never exits early between frames.

## Methods

### Public methods

- [`StreamClient$new()`](#method-StreamClient-new)

- [`StreamClient$on()`](#method-StreamClient-on)

- [`StreamClient$on_event()`](#method-StreamClient-on_event)

- [`StreamClient$connect()`](#method-StreamClient-connect)

- [`StreamClient$send()`](#method-StreamClient-send)

- [`StreamClient$run()`](#method-StreamClient-run)

- [`StreamClient$close()`](#method-StreamClient-close)

- [`StreamClient$is_open()`](#method-StreamClient-is_open)

- [`StreamClient$clone()`](#method-StreamClient-clone)

------------------------------------------------------------------------

### Method `new()`

Initialise a StreamClient

#### Usage

    StreamClient$new(
      url,
      auto_reconnect = TRUE,
      max_reconnects = Inf,
      backoff_cap = 60,
      proactive_reconnect = NULL,
      stale_timeout = NULL,
      keepalive = 30
    )

#### Arguments

- `url`:

  (scalar\<character\>) the WebSocket URL (`ws://` or `wss://`).

- `auto_reconnect`:

  (scalar\<logical\>) reconnect automatically (with backoff) when the
  socket drops. Default `TRUE`.

- `max_reconnects`:

  (scalar\<numeric\>) give up after this many consecutive failed
  reconnects (emit `"giveup"`, then `$run()` exits so a supervisor can
  restart). `Inf` (default) retries forever — the right choice for an
  unattended recorder.

- `backoff_cap`:

  (scalar\<numeric in \]0, Inf\[\>) maximum backoff delay in seconds
  before the jitter floor. Default `60`.

- `proactive_reconnect`:

  (scalar\<numeric in \]0, Inf\[\> \| NULL) reconnect proactively this
  many seconds after opening (e.g. `82800` = 23h to beat a 24h cutoff).
  `NULL` (default) disables it.

- `stale_timeout`:

  (scalar\<numeric in \]0, Inf\[\> \| NULL) force a reconnect if no
  frame arrives within this many seconds (silence watchdog). `NULL`
  (default) disables it.

- `keepalive`:

  (scalar\<numeric in \]0, Inf\[\>) interval in seconds of the internal
  keepalive tick (also the watchdog's check granularity). Default `30`.

#### Returns

(class\<StreamClient\>) invisibly, self.

------------------------------------------------------------------------

### Method `on()`

Register an Event Handler (Node-style `ws.on`)

The event set is open: register handlers for the standard events (see
the class description) or for any name a subclass' `.dispatch()` emits.

#### Usage

    StreamClient$on(event, handler)

#### Arguments

- `event`:

  (scalar\<character\>) the event name.

- `handler`:

  (function) called when the event fires, with that event's payload.

#### Returns

(class\<StreamClient\>) invisibly, self (chainable).

------------------------------------------------------------------------

### Method `on_event()`

Register a Typed Lifecycle-Event Handler

A parallel, structured surface to `$on()`. Where `$on(event, handler)`
delivers each event's raw callback payload under a string key,
`$on_event()` delivers a single **typed** object (see
[ws_event](https://dereckscompany.github.io/connectcore/reference/ws_event.md))
for every lifecycle transition — `open`, `message`, `close`, `error`,
`reconnect` — each with a lubridate UTC `timestamp` and per-type fields
(a `close` carries `code` and `reason`; a `reconnect` carries `attempt`
and `delay`; ...). This is the WebSocket analogue of the typed REST
conditions: branch on `event$event_type` (against
[WS_EVENT_TYPES](https://dereckscompany.github.io/connectcore/reference/WS_EVENT_TYPES.md))
and read fields as data.

It is **additive**: the raw `$on()` callbacks fire exactly as before, so
an existing consumer is unaffected. The typed object is built only when
at least one `$on_event()` handler is registered, so the parse-free hot
path stays free when nothing listens.

#### Usage

    StreamClient$on_event(handler)

#### Arguments

- `handler`:

  (function) called with a typed lifecycle event (see
  [ws_event](https://dereckscompany.github.io/connectcore/reference/ws_event.md))
  on every lifecycle transition.

#### Returns

(class\<StreamClient\>) invisibly, self (chainable).

------------------------------------------------------------------------

### Method `connect()`

Open the Connection

Wires the socket callbacks and starts connecting, then returns
immediately (non-blocking) — handlers only fire once something pumps
`later`. Idempotent: a no-op if already connecting or open. Use `$run()`
to drive the loop yourself, or call `$connect()` when the client lives
inside a host that already runs a `later` loop.

#### Usage

    StreamClient$connect()

#### Returns

(class\<StreamClient\>) invisibly, self.

------------------------------------------------------------------------

### Method `send()`

Send a Raw Message

#### Usage

    StreamClient$send(message)

#### Arguments

- `message`:

  (scalar\<character\>) a string to send on the socket (typically a JSON
  control/subscribe frame).

#### Returns

(class\<StreamClient\>) invisibly, self.

------------------------------------------------------------------------

### Method `run()`

Run the Event Loop (keep the process alive)

Connects if needed, then blocks and pumps R's `later` event loop so
handlers keep firing. Runs until `$close()` is called or reconnects are
exhausted. Teardown is clean and guaranteed — a normal close, an
interrupt (Ctrl-C), or an error all close the socket and cancel timers
via [`on.exit()`](https://rdrr.io/r/base/on.exit.html). An interrupt
returns quietly; any other error still propagates after cleanup.

#### Usage

    StreamClient$run(timeout = 0.1)

#### Arguments

- `timeout`:

  (scalar\<numeric in \]0, Inf\[\>) seconds each
  [`later::run_now()`](https://later.r-lib.org/reference/run_now.html)
  tick waits for work before looping (keeps CPU near zero between
  messages). Default `0.1`.

#### Returns

(class\<StreamClient\>) invisibly, self.

------------------------------------------------------------------------

### Method [`close()`](https://rdrr.io/r/base/connections.html)

Close the Connection

Stops auto-reconnect, cancels timers, and closes the socket. After this,
`$run()` returns.

#### Usage

    StreamClient$close()

#### Returns

(class\<StreamClient\>) invisibly, self.

------------------------------------------------------------------------

### Method `is_open()`

Is the Socket Open?

#### Usage

    StreamClient$is_open()

#### Returns

(scalar\<logical\>) `TRUE` if the socket is open.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    StreamClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
if (FALSE) { # \dontrun{
# A minimal recorder: subclass and override .dispatch to classify, or just use
# the default "message" event and append the raw text to a file.
ws <- StreamClient$new("wss://example.org/stream", stale_timeout = 120)
ws$on("open", function(e) ws$send('{"subscribe":"all"}'))
ws$on("message", function(msg) cat(msg, "\n"))
ws$run() # keeps the process alive and pumps the event loop
} # }
```
