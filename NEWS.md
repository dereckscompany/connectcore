# connectcore 0.0.1

Initial release. A shared transport base for R data-source connectors. It owns
**transport only** — no trading vocabulary, no dependency on `tradebot-core` — and
is meant to be installed and **extended** by connector packages rather than used on
its own. (The exported helpers and `StreamClient` do work standalone; `RestClient`
is extend-only, its request funnel being private.)

* **`RestClient`** — abstract REST base: synchronous or asynchronous (via
  `promises`), optional retry and client-side throttle, and one private
  `.request()` funnel every endpoint method delegates to. Venue specifics plug in
  by overriding two private seams — `.sign()` (authenticate a request) and
  `.parse_envelope()` (response → data, raise on error). The defaults are no-auth
  and "JSON body, error on non-2xx", so a simple public API works unextended.

* **`StreamClient`** — concrete, event-driven WebSocket base (`$on(event, handler)`,
  Node-style) with full-jitter auto-reconnect, keepalive, a silence watchdog, and
  proactive reconnect. Subclasses override `.dispatch()` (frame → events) and
  `.resubscribe()` (replay subscriptions); a recorder needs no subclass at all.

* **Helpers** — HMAC-query request signing (`hmac_query_sign()`), JSON →
  `data.table` coercion, epoch ↔ `POSIXct` conversion, environment-backed
  credential loading, and WebSocket backoff. Every argument and return is typed and
  runtime-checked with [roxyassert](https://github.com/dereckscompany/roxyassert).
