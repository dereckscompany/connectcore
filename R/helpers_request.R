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
    rlang::abort(paste0("HTTP error ", status, "\n", body_text))
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
    rlang::abort(sprintf("Failed to fetch server time: response has no '%s' field.", field))
  }
  return(assert_return_fetch_server_time_ms(as.numeric(value)))
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
#' `req_retry` and `req_throttle` — retry/backoff and client-side rate limiting
#' that no individual connector currently has.
#'
#' Signing runs **after** the body is set, so a venue that signs the exact body
#' bytes (`body_format = "raw"`) can read them off `req$body$data` inside `sign`
#' and add the signature header before the request is performed.
#'
#' @param base_url (scalar<character>) the API base URL.
#' @param endpoint (scalar<character>) the path appended to `base_url`.
#' @param method (scalar<character>) the HTTP method. Default `"GET"`.
#' @param query (list) query parameters; `NULL` entries are dropped. A
#'   vector-valued entry repeats its key (`.multi = "explode"`), e.g.
#'   `ids = c("A", "B")` becomes `ids=A&ids=B`.
#' @param body (list | scalar<character> | raw | NULL) request body. For
#'   `body_format = "raw"` it is a pre-serialized scalar `character` (or `raw`)
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
#'   or re-encoding (the caller owns serialization; required by venues that sign
#'   the exact body bytes). Default `"json"`.
#' @param raw_content_type (scalar<character>) the `Content-Type` for a `"raw"`
#'   body. Ignored unless `body_format = "raw"`. Default `"application/json"`.
#' @param .perform (function) the httr2 perform function
#'   ([httr2::req_perform] or [httr2::req_perform_promise]). Default
#'   [httr2::req_perform].
#' @param .parser (function) post-processor applied to the parsed data. Default
#'   [base::identity].
#' @param is_async (scalar<logical>) whether `.perform` returns a promise. Default
#'   `FALSE`.
#' @param timeout (scalar<numeric in ]0, Inf[>) request timeout in seconds.
#'   Default `30`.
#' @param user_agent (scalar<character>) the `User-Agent` header. Default
#'   `"dereckscompany/connectcore"`.
#' @param max_tries (scalar<count in [1, Inf[>) retry up to this many times with
#'   backoff on a transient failure. `1` (default) disables retry.
#' @param throttle_rate (scalar<numeric in ]0, Inf[> | NULL) client-side rate cap
#'   in requests per second. `NULL` (default) disables throttling.
#' @param ctx (list) extra context forwarded to `sign` (e.g. a timestamp source).
#'   Default `list()`.
#' @return (any) the post-processed data, or a promise resolving to it.
#' @importFrom httr2 request req_method req_url_path_append req_url_query req_body_json
#'   req_body_raw req_timeout req_user_agent req_error req_retry req_throttle req_perform
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
  throttle_rate = NULL,
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
    throttle_rate,
    ctx
  )

  req <- httr2::request(base_url)
  req <- httr2::req_url_path_append(req, endpoint)
  req <- httr2::req_method(req, method)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_user_agent(req, user_agent)

  query <- query[!vapply(query, is.null, logical(1))]
  # A raw body is pre-serialized and sent byte-verbatim, so it must NOT be
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
    # re-encoding. The caller owns serialization; a body-signing venue's `sign`
    # can then read the exact bytes off `req$body$data` below.
    req <- httr2::req_body_raw(req, body, type = raw_content_type)
  }

  # The envelope parser owns error detection, so disable httr2's auto-error.
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  if (max_tries > 1L) {
    req <- httr2::req_retry(req, max_tries = as.integer(max_tries))
  }
  if (!is.null(throttle_rate)) {
    req <- httr2::req_throttle(req, rate = throttle_rate)
  }
  if (!is.null(keys) && !is.null(sign)) {
    req <- sign(req, keys, ctx)
  }

  result <- .perform(req)
  return(then_or_now(
    result,
    function(resp) .parser(parse_envelope(resp)),
    is_async = is_async
  ))
}
