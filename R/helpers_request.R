# File: R/helpers_request.R
# Core HTTP request infrastructure: the single sync/async funnel every REST call
# flows through, plus the default response parser, a server-time fetcher, and a
# monotonic nonce. Venue specifics (signing, error-envelope shape) plug in as
# functions rather than being baked in here.

#' Apply a continuation to a value or a promise
#'
#' The single sync/async branching point. Routes a value through `fn` either
#' synchronously or as a [promises::promise], depending on `is_async`. A connector
#' writes its methods mode-agnostically and only chooses `is_async` once.
#'
#' @param x (any) a value, or a [promises::promise] resolving to one.
#' @param fn (function) applied to the (resolved) value of `x`.
#' @param is_async (scalar<logical>) if `TRUE`, return `promises::then(x, fn)`;
#'   otherwise return `fn(x)`. Default `FALSE`.
#' @return (any) `fn(x)`, or a promise resolving to it.
#' @export
then_or_now <- function(x, fn, is_async = FALSE) {
  assert_args_then_or_now(x, fn, is_async)
  if (is_async) {
    return(promises::then(x, fn))
  }
  return(fn(x))
}

#' Default response parser: JSON body, error on non-2xx
#'
#' A generic [httr2::response] -> data parser: returns the parsed JSON body, and
#' raises on a non-2xx HTTP status. Connectors with a business-level error
#' envelope (e.g. a `code`/`msg` field that signals failure on a 200) supply their
#' own `parse_envelope` to [build_request()] instead; this is the sensible default
#' when the HTTP status alone tells the truth.
#'
#' @param resp (class<httr2_response>) the response to parse.
#' @return (any) the parsed JSON body (lists, with `simplifyVector = FALSE`).
#' @importFrom httr2 resp_status resp_body_json resp_body_string
#' @export
parse_json_response <- function(resp) {
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "<unreadable body>")
    # Typed condition (see [connectcore_conditions]): message stays byte-identical to
    # the legacy `paste0("HTTP error ", status, "\n", body_text)`; classes/fields are
    # additive, so a caller can tryCatch by status and read $status/$url instead of
    # grepping the string.
    abort_api_error(
      status = status,
      url = resp$url,
      body = body_text,
      message = paste0("HTTP error ", status, "\n", body_text)
    )
  }
  return(httr2::resp_body_json(resp, simplifyVector = FALSE))
}

#' Fetch a server's time in epoch milliseconds
#'
#' A lightweight synchronous GET against a server-time endpoint, returning epoch
#' milliseconds. Used when signing against the server clock instead of the local
#' one (to avoid drift). The `field` is the JSON key holding the time.
#'
#' @param base_url (scalar<character>) the API base URL.
#' @param time_endpoint (scalar<character>) the path of the time endpoint.
#' @param field (scalar<character>) the response JSON key holding epoch ms.
#'   Default `"serverTime"`.
#' @return (scalar<numeric>) server time in epoch milliseconds.
#' @importFrom httr2 request req_url_path_append req_method req_timeout req_perform resp_body_json
#' @export
fetch_server_time_ms <- function(base_url, time_endpoint, field = "serverTime") {
  assert_args_fetch_server_time_ms(base_url, time_endpoint, field)
  req <- httr2::request(base_url)
  req <- httr2::req_url_path_append(req, time_endpoint)
  req <- httr2::req_method(req, "GET")
  req <- httr2::req_timeout(req, 5)
  parsed <- httr2::resp_body_json(httr2::req_perform(req), simplifyVector = FALSE)
  value <- parsed[[field]]
  if (is.null(value)) {
    # Typed condition (see [connectcore_conditions]): message stays byte-identical;
    # a caller can tryCatch(connectcore_response_error = ...) and read $field.
    abort_response_error(
      message = sprintf("Failed to fetch server time: response has no '%s' field.", field),
      field = field
    )
  }
  return(assert_return_fetch_server_time_ms(as.numeric(value)))
}

# ---- Hard outer deadline (both branches end up classed `connectcore_request_deadline`) ----
#
# `httr2::req_timeout()` is reliable on the SYNCHRONOUS branch: it is a plain
# `curl::curl_fetch_memory()` call, and curl enforces its own `CURLOPT_TIMEOUT`
# regardless of who is watching -- confirmed empirically (see NEWS, this
# release) at ~1s past a 1s timeout against a stub server that accepts the TCP
# connection and never writes a byte.
#
# The ASYNCHRONOUS branch (`req_perform_promise()`) is NOT reliable against the
# same stub: the promise did not settle within 5-8s of actively pumping
# `later::run_now()`. The root cause traces into httr2 1.2.2's own pool poller
# (`httr2:::ensure_pool_poller()`), which re-arms itself with
# `later::later_fd(timeout = curl::multi_fdset(pool)$timeout)`; `curl::multi_fdset()`
# reports that timeout in MILLISECONDS (matching libcurl's own
# `curl_multi_timeout()`), but `later::later_fd()`'s `timeout` is documented in
# SECONDS. The poller therefore re-arms for roughly `timeout_secs * 1000`
# real seconds (around 8.3 hours at this package's 30s `RestClient` default)
# rather than the ~30s a caller would expect -- a suspected httr2 bug, reported
# upstream, but not something this package can wait on (see NEWS). Confirmed
# by direct reproduction: an abandoned request on the DEFAULT (shared) curl
# pool left that pool's poller parked long enough that a second, wholly
# unrelated request to a fast, responsive host on the SAME pool also failed to
# settle within ten seconds, with two handles stuck in `curl::multi_list()`.
# On a resident container every connector call shares that one default pool,
# so a single stalled request would silently freeze EVERY later async call for
# the rest of the process's life, not just the one that stalled.
#
# The fix has two parts:
#  1. A hard outer deadline: race the request promise against a `later::later()`
#     timer set at `timeout + deadline_margin` (`promises::promise_race()`), so
#     the promise this function returns always settles, regardless of whether
#     or when httr2's own timeout ever fires.
#  2. Give every asynchronous request its OWN `curl::new_pool()` (never the
#     shared default), and CANCEL every handle left in that pool
#     (`curl::multi_cancel()`) the moment the deadline timer fires, before
#     rejecting. This releases the stuck file descriptor immediately and keeps
#     the poisoned state confined to a pool nobody else will ever touch again,
#     instead of letting it accumulate in (and eventually freeze) the shared
#     default pool. The trade-off: a per-request pool means no HTTP keep-alive
#     / connection reuse across separate asynchronous calls -- each one pays a
#     fresh TCP (and TLS, where applicable) handshake. That is judged strictly
#     preferable to a single stalled request being able to freeze the venue for
#     the rest of the process's life. Cancelling on OUR deadline reclaims the
#     fd immediately; a request that settles (success or its own failure)
#     BEFORE the deadline disarms the timer the same way, so a successful call
#     never pins its pool/socket for the full window. If something stops this
#     package's own cancellation from ever running (the process itself wedged,
#     not just one request), the underlying httr2 poller for that one orphaned
#     pool is still only on the suspected `timeout_secs * 1000` horizon above --
#     so a live `timeout`/`deadline_margin` should stay modest (seconds, not
#     minutes): the bigger they are, the longer that worst-case horizon gets.
#
# The synchronous branch does not need a pool or a second timer (its own
# req_timeout() already works) -- it only needs its existing curl timeout
# RECLASSIFIED into the same condition, so a caller catches one class
# regardless of which mode is in use. Note `timeout` is enforced PER ATTEMPT:
# when `max_tries > 1`, httr2 runs the full retry/backoff sequence for a
# transient failure INSIDE one `.perform(req)` call before ever raising, so
# `elapsed` below already reflects that whole sequence, not a single try --
# but it means the time-to-failure can legitimately exceed `timeout` by a wide
# margin when retries are configured. The asynchronous (pooled) path has no
# such concern: `req_retry()`/`req_throttle()` policies are not honoured by
# httr2's pooled/promise request path at all (a pre-existing httr2 limitation,
# unrelated to this fix).

# The (method, host, path) a deadline condition reports. The query string is
# always dropped entirely (not merely redacted) -- see `abort_request_deadline()`
# for why that is stricter than the `scrub_url()` treatment the other
# conditions use.
.deadline_request_fields <- function(req, method) {
  parsed <- httr2::url_parse(req$url)
  return(list(method = toupper(method), host = parsed$hostname, path = parsed$path))
}

# Seconds elapsed from `started_at` to now, via lubridate (never base
# Sys.time()/difftime() arithmetic).
.elapsed_secs <- function(started_at) {
  return(lubridate::time_length(lubridate::interval(started_at, lubridate::now("UTC")), "seconds"))
}

# Build (but do not signal) the classed deadline condition, so it can be handed
# to a promise's `reject()` instead of thrown, or re-signalled with
# `rlang::cnd_signal()`. `call` is the environment the condition should report
# as raised from (see the two call sites below): without it, the condition
# would print as raised inside this internal helper rather than inside the
# public `build_request()` call the caller actually made.
.deadline_condition <- function(fields, started_at, call) {
  elapsed <- .elapsed_secs(started_at)
  return(tryCatch(
    abort_request_deadline(
      method = fields$method,
      host = fields$host,
      path = fields$path,
      elapsed = elapsed,
      call = call
    ),
    error = function(e) e
  ))
}

# Was this synchronous failure httr2/curl's own `req_timeout()` firing? Curl
# tags a genuine operation timeout with `curl_error_operation_timedout` on the
# wrapped `$parent` condition; anything else (DNS failure, connection refused,
# TLS failure, a non-timeout curl error, ...) is rethrown unchanged.
.is_timeout_failure <- function(e) {
  return(inherits(e, "httr2_failure") && inherits(e[["parent"]], "curl_error_operation_timedout"))
}

# Synchronous branch: perform the request, reclassifying a genuine req_timeout()
# failure into `connectcore_request_deadline`; any other error is re-signalled
# unchanged via `rlang::cnd_signal()` (never a bare `stop()`).
.perform_sync_with_deadline <- function(perform_once, fields, started_at, call) {
  return(tryCatch(
    perform_once(),
    error = function(e) {
      if (.is_timeout_failure(e)) {
        return(rlang::cnd_signal(.deadline_condition(fields, started_at, call)))
      }
      return(rlang::cnd_signal(e))
    }
  ))
}

# Asynchronous branch: give the request its OWN curl pool (never the shared
# default -- see the file-header note on why), then race its promise against a
# `later()` timer set at `deadline_secs`, so the returned promise always
# settles. If the timer wins, every handle still in `pool` is cancelled before
# rejecting, releasing the stuck file descriptor at once and confining the
# abandoned request to a pool nothing else will ever touch; whatever the real
# request eventually resolves or rejects with after that is never read by
# anything downstream, so a late response is discarded, never delivered.
# `request_promise` is forced FIRST, before the timer is armed, so a
# SYNCHRONOUS throw from `.perform()` (e.g. a bad `pool` argument) propagates
# immediately instead of leaving a dangling timer that would later reject a
# promise this function never got to return.
#
# Two further edges this function closes, both found by review:
#  - If the request settles FIRST (success or its own failure), the deadline
#    timer is disarmed immediately (`cancel_timer()`). Without this, every
#    SUCCESSFUL call would still pin its private pool, this closure, and an
#    open keep-alive socket for the full `deadline_secs` (35s at this
#    package's defaults) -- a slow fd/memory leak under steady load.
#  - httr2's own timeout CAN still fire on the pooled path (just not
#    reliably -- see the file header): a venue answering after `timeout` but
#    before `timeout + deadline_margin` surfaces as curl's raw
#    `httr2_failure` otherwise, carrying the signed request (headers, signed
#    URL) on its `request` field -- a credential leak, and a contradiction of
#    "both branches surface the same credential-free deadline class". The
#    request promise is wrapped (`guarded`) to reclassify that one case into
#    the SAME condition our own timer raises, before racing it; a non-timeout
#    rejection (DNS failure, connection refused, ...) is re-signalled
#    completely unchanged.
.perform_async_with_deadline <- function(request_promise, pool, deadline_secs, fields, started_at, call) {
  force(request_promise)
  cancel_timer <- NULL
  timer <- promises::promise(function(resolve, reject) {
    cancel_timer <<- later::later(
      function() {
        handles <- curl::multi_list(pool)
        for (h in handles) {
          curl::multi_cancel(h)
        }
        return(reject(.deadline_condition(fields, started_at, call)))
      },
      delay = deadline_secs
    )
    return(invisible(cancel_timer))
  })
  promises::then(
    request_promise,
    onFulfilled = function(v) {
      return(cancel_timer())
    },
    onRejected = function(e) {
      return(cancel_timer())
    }
  )
  guarded <- promises::then(
    request_promise,
    onRejected = function(e) {
      if (.is_timeout_failure(e)) {
        return(rlang::cnd_signal(.deadline_condition(fields, started_at, call)))
      }
      return(rlang::cnd_signal(e))
    }
  )
  return(promises::promise_race(guarded, timer))
}

# Package-private monotonic nonce state: max(last + 1, now_ms), so two calls in
# the same millisecond still strictly increase. Used by nonce-based signed APIs.
.nonce_state <- new.env(parent = emptyenv())
.nonce_state$last <- 0

#' Next monotonic nonce (epoch milliseconds, strictly increasing)
#'
#' Returns `max(previous + 1, now_ms)`, so successive calls strictly increase even
#' within the same millisecond. Some signed APIs require a strictly-monotonic
#' nonce per credential to reject replays.
#'
#' @return (scalar<numeric>) a strictly increasing epoch-millisecond nonce.
#' @importFrom lubridate now
#' @export
next_nonce <- function() {
  now_ms <- floor(as.numeric(lubridate::now("UTC")) * 1000)
  nonce <- max(.nonce_state$last + 1, now_ms)
  .nonce_state$last <- nonce
  return(nonce)
}

#' Build and perform a REST request (the single funnel)
#'
#' Constructs an [httr2::request], optionally signs it, performs it (sync or
#' async), parses the response envelope, and applies a post-parser. Every REST
#' call a connector makes flows through here. Venue specifics are injected:
#' `sign` (how to authenticate), `parse_envelope` (how to turn a response into
#' data and detect errors), and `body_format` (how a request body is encoded).
#'
#' Unlike the per-venue copies this generalises, it also adds optional
#' `req_retry` (gated on idempotency — see the retry-safety rule below) and
#' `req_throttle` — retry/backoff and client-side rate limiting that no
#' individual connector previously had.
#'
#' Signing runs **after** the body is set, so a venue that signs the exact body
#' bytes (`body_format = "raw"`) can read them off `req$body$data` inside `sign`
#' and add the signature header before the request is performed.
#'
#' @details
#' **Retry safety (hard rule).** Retry is attached only when `max_tries > 1`
#' **and** `idempotent` is `TRUE`. `idempotent` defaults to `TRUE` for `GET` and
#' `FALSE` for every other verb, so an order submission is never auto-retried by
#' default and can never be silently resent and double-submitted. A venue whose
#' reads are POST (the query is encoded in the request body) MAY pass
#' `idempotent = TRUE` on that read path to opt it into retry. A **write** (an
#' order submission, a cancel) must **NEVER** be marked `idempotent = TRUE` — a
#' resend could double-submit. In live trading the trader layer is the single
#' retry authority (it routes by typed error class and manages cooldowns); this
#' funnel-level convenience is for research and backfill reads only. The transient
#' set is 408, 429, any 5xx, and connection failures; `Retry-After` is honoured.
#'
#' **The request deadline (hard rule).** `req_timeout()` is reliable on the
#' synchronous branch (plain `curl::curl_fetch_memory()`; curl enforces its own
#' `CURLOPT_TIMEOUT` unconditionally). It is NOT reliable on the asynchronous
#' branch (`req_perform_promise()`), and the reason is now understood: httr2
#' 1.2.2's own pool poller re-arms a `later::later_fd()` wait using curl's
#' remaining-timeout value in MILLISECONDS where `later_fd()` expects SECONDS
#' (a suspected httr2 bug, reported upstream — see NEWS — but not something
#' this package can wait on), so a stalled request's own timeout check is
#' effectively parked for `timeout_secs * 1000` real seconds (around 8.3 hours
#' at this package's 30s `RestClient` default) rather than firing at `timeout`.
#' Because httr2's default pool is shared process-wide, one such stall silently
#' freezes the poller for every OTHER asynchronous request too (confirmed by
#' reproduction), which is exactly the production incident this guards against
#' (2026-09-28: a 10-second documented timeout, a 600-second hang). The fix has
#' two parts: every asynchronous request now runs in its OWN `curl::new_pool()`
#' rather than httr2's shared default (the trade-off: no HTTP keep-alive across
#' separate asynchronous calls, judged preferable to one stalled request
#' freezing the venue for the process's life), and its promise is additionally
#' raced (`promises::promise_race()`) against a `later::later()` timer armed for
#' `timeout + deadline_margin` seconds — whichever settles first wins, and if
#' the timer wins, every handle left in that request's own pool is actively
#' cancelled (releasing the stuck file descriptor at once) before the promise
#' this function returns rejects; a response that arrives after that is
#' discarded, never delivered to the caller. When the REQUEST settles first
#' instead (success or its own failure), the deadline timer is disarmed
#' immediately, so a successful call never pins its pool, closures, and an
#' open keep-alive socket for the full `timeout + deadline_margin` window —
#' and because httr2's own timeout can still fire on the pooled path (just not
#' reliably), a venue answering after `timeout` but before the outer deadline
#' is reclassified into the same condition rather than left as a raw failure
#' carrying the signed request. Both branches therefore surface a timeout the
#' same way: a classed `connectcore_request_deadline` condition (see
#' [abort_request_deadline()]) carrying the method, host, query-stripped path,
#' and elapsed seconds — never the query string, headers, or body, so a
#' signature or API key is never in the error. One edge this cannot close: a
#' caller that itself blocks the event loop (e.g. a long synchronous
#' computation between polls of `later::run_now()`) for longer than `timeout`
#' cannot observe a success that arrived during that block — by the time
#' control returns to the loop the deadline has already fired and that success
#' is discarded like any other late response; keep the caller's own loop
#' responsive relative to `timeout`. `timeout` (and so the deadline)
#' is enforced PER ATTEMPT: with `max_tries > 1` the synchronous branch's
#' `elapsed` already reflects a full retry/backoff sequence (httr2 runs it
#' inside the one call this funnel makes), which can legitimately exceed
#' `timeout` by a wide margin; the asynchronous (pooled) path has no such
#' concern because `req_retry()`/`req_throttle()` are not honoured on it at all
#' (a pre-existing httr2 limitation, unrelated to this fix).
#'
#' @param base_url (scalar<character>) the API base URL.
#' @param endpoint (scalar<character>) the path appended to `base_url`.
#' @param method (scalar<character>) the HTTP method. Default `"GET"`.
#' @param query (list) query parameters; `NULL` entries are dropped. A
#'   vector-valued entry repeats its key (`.multi = "explode"`), e.g.
#'   `ids = c("A", "B")` becomes `ids=A&ids=B`.
#' @param body (list | scalar<character> | raw | NULL) request body. For
#'   `body_format = "raw"` it is a pre-serialised scalar `character` (or `raw`)
#'   sent verbatim; otherwise a `list` whose `NULL` entries are dropped. Default
#'   `NULL`.
#' @param keys (list | NULL) credentials passed to `sign`; `NULL` skips signing.
#' @param sign (function | NULL) `function(req, keys, ctx)` returning a signed
#'   request. `NULL` (default) means no signing.
#' @param parse_envelope (function) `function(resp)` turning a response into data,
#'   raising on error. Default [parse_json_response()].
#' @param body_format (scalar<character in c("json", "query", "none", "raw")>) how
#'   `body` is encoded: a pretty-printed JSON body (`NULL` fields pruned), merged
#'   into the query string (some signed APIs), ignored, or — for `"raw"` — sent
#'   byte-verbatim via [httr2::req_body_raw()] with no pruning, pretty-printing,
#'   or re-encoding (the caller owns serialisation; required by venues that sign
#'   the exact body bytes). Default `"json"`.
#' @param raw_content_type (scalar<character>) the `Content-Type` for a `"raw"`
#'   body. Ignored unless `body_format = "raw"`. Default `"application/json"`.
#' @param .perform (function) the httr2 perform function
#'   ([httr2::req_perform] or [httr2::req_perform_promise]). Default
#'   [httr2::req_perform]. When `is_async = TRUE` this is always called as
#'   `.perform(req, pool = pool)` (never with one argument) so each
#'   asynchronous request gets its own dedicated `curl` pool (see Details) --
#'   a custom asynchronous `.perform` MUST accept a `pool` argument, e.g.
#'   `function(req, pool = NULL) ...`. The synchronous branch is still called
#'   as `.perform(req)` with one argument, unchanged.
#' @param .parser (function) post-processor applied to the parsed data. Default
#'   [base::identity].
#' @param is_async (scalar<logical>) whether `.perform` returns a promise. Default
#'   `FALSE`.
#' @param timeout (scalar<numeric in ]0, Inf[>) request timeout in seconds.
#'   Default `30`.
#' @param user_agent (scalar<character>) the `User-Agent` header. Default
#'   `"dereckscompany/connectcore"`.
#' @param max_tries (scalar<count in [1, Inf[>) for an **idempotent** request
#'   only (see `idempotent`), retry up to this many times with jittered backoff
#'   on a transient failure (408, 429, any 5xx, or a connection failure;
#'   `Retry-After` honoured). `1` (default) disables retry.
#' @param idempotent (scalar<logical>) whether this request is safe to re-send.
#'   Retry is attached only when `max_tries > 1` **and** this is `TRUE`. Defaults
#'   to `TRUE` for `GET` and `FALSE` for every other verb, so a non-`GET` verb is
#'   never auto-retried by default. A venue whose reads are POST (query in the
#'   body) may pass `TRUE` on that read path; a write (order submission, cancel)
#'   must NEVER be marked idempotent (see the retry-safety rule in Details).
#' @param throttle_rate (scalar<numeric in ]0, Inf[> | NULL) client-side rate cap
#'   in requests per second. `NULL` (default) disables throttling.
#' @param deadline_margin (scalar<numeric in ]0, Inf[>) extra seconds of grace
#'   added to `timeout` before the asynchronous branch's own hard outer deadline
#'   fires (see Details). Ignored on the synchronous branch, whose own
#'   `req_timeout()` already fires reliably at `timeout`. Default `5`.
#' @param ctx (list) extra context forwarded to `sign` (e.g. a timestamp source).
#'   Default `list()`.
#' @return (any) the post-processed data, or a promise resolving to it.
#' @importFrom httr2 request req_method req_url_path_append req_url_query
#'   req_body_raw req_timeout req_user_agent req_error req_retry req_throttle req_perform
#'   url_parse
#' @importFrom promises promise promise_race
#' @importFrom later later
#' @importFrom lubridate now interval time_length
#' @importFrom curl new_pool multi_list multi_cancel
#' @importFrom rlang cnd_signal
#' @export
build_request <- function(
  base_url,
  endpoint,
  method = "GET",
  query = list(),
  body = NULL,
  keys = NULL,
  sign = NULL,
  parse_envelope = parse_json_response,
  body_format = c("json", "query", "none", "raw"),
  raw_content_type = "application/json",
  .perform = httr2::req_perform,
  .parser = identity,
  is_async = FALSE,
  timeout = 30,
  user_agent = "dereckscompany/connectcore",
  max_tries = 1L,
  idempotent = identical(toupper(method), "GET"),
  throttle_rate = NULL,
  deadline_margin = 5,
  ctx = list()
) {
  body_format <- match.arg(body_format)
  assert_args_build_request(
    base_url,
    endpoint,
    method,
    query,
    body,
    keys,
    sign,
    parse_envelope,
    body_format,
    raw_content_type,
    .perform,
    .parser,
    is_async,
    timeout,
    user_agent,
    max_tries,
    idempotent,
    throttle_rate,
    deadline_margin,
    ctx
  )

  req <- httr2::request(base_url)
  req <- httr2::req_url_path_append(req, endpoint)
  req <- httr2::req_method(req, method)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_user_agent(req, user_agent)

  query <- query[!vapply(query, is.null, logical(1))]
  # A raw body is pre-serialised and sent byte-verbatim, so it must NOT be
  # NULL-pruned (that operates on a list and would corrupt the exact bytes).
  if (body_format != "raw" && !is.null(body)) {
    body <- body[!vapply(body, is.null, logical(1))]
  }
  if (body_format == "query" && length(body) > 0L) {
    query <- c(query, body) # signed APIs that carry the body in the query string
  }
  if (length(query) > 0L) {
    # `.multi = "explode"` repeats the key for a vector value (`ids = c("A", "B")`
    # -> `ids=A&ids=B`), the standard REST multi-value convention. httr2 defaults
    # to `.multi = "error"`, which aborts on any length > 1 value; scalar values
    # are unaffected either way.
    req <- httr2::req_url_query(req, !!!query, .multi = "explode")
  }
  if (body_format == "json" && length(body) > 0L) {
    req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  }
  if (body_format == "raw" && !is.null(body)) {
    # Verbatim: no req_body_json, no NULL-pruning, no pretty-printing, no
    # re-encoding. The caller owns serialisation; a body-signing venue's `sign`
    # can then read the exact bytes off `req$body$data` below.
    req <- httr2::req_body_raw(req, body, type = raw_content_type)
  }

  # The envelope parser owns error detection, so disable httr2's auto-error.
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  # Retry is gated on idempotency, never the verb alone. `idempotent` defaults to
  # TRUE only for GET, so by default a non-idempotent verb (an order POST, a
  # cancel DELETE) is performed exactly once even when max_tries > 1 and can never
  # be silently resent and double-submitted. A venue whose reads are POST (its
  # query is encoded in the body) may pass idempotent = TRUE on that read path to
  # opt it into retry; it must NEVER pass idempotent = TRUE on a write. In live
  # trading the trader layer is the single retry authority (it routes by typed
  # error class and manages cooldowns); this funnel-level convenience serves
  # research and backfill reads that opt in. Transient set: 408, 429, and any 5xx,
  # plus connection failures (safe to re-send for an idempotent request).
  # Retry-After is honoured by httr2's default backoff.
  if (max_tries > 1L && isTRUE(idempotent)) {
    req <- httr2::req_retry(
      req,
      max_tries = as.integer(max_tries),
      retry_on_failure = TRUE,
      is_transient = function(resp) {
        status <- httr2::resp_status(resp)
        return(status %in% c(408L, 429L) || status >= 500L)
      }
    )
  }
  if (!is.null(throttle_rate)) {
    req <- httr2::req_throttle(req, rate = throttle_rate)
  }
  if (!is.null(keys) && !is.null(sign)) {
    req <- sign(req, keys, ctx)
  }

  started_at <- lubridate::now("UTC")
  deadline_fields <- .deadline_request_fields(req, method)
  # A plain call VALUE (not an environment reference), captured here so a
  # deadline condition reports as raised from this public build_request()
  # call, not from an internal helper several frames down. This matters most
  # on the asynchronous branch: by the time the deadline timer fires,
  # build_request() has long since returned and its frame is no longer live,
  # so an environment-based `call` (e.g. rlang::current_env()) silently loses
  # its attribution there, printing a bare "Error:" -- a detached call OBJECT
  # like sys.call() keeps working because it does not depend on the frame
  # still being on the stack.
  call_obj <- sys.call()

  result <- NULL
  if (is_async) {
    pool <- curl::new_pool() # never the shared default pool -- see the file-header note above
    result <- .perform_async_with_deadline(
      .perform(req, pool = pool),
      pool,
      timeout + deadline_margin,
      deadline_fields,
      started_at,
      call_obj
    )
  } else {
    result <- .perform_sync_with_deadline(function() .perform(req), deadline_fields, started_at, call_obj)
  }

  return(then_or_now(
    result,
    function(resp) .parser(parse_envelope(resp)),
    is_async = is_async
  ))
}
