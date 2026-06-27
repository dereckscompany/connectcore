# File: R/mock.R
# A shared HTTP-mock test harness for connector packages. httr2 exposes a native
# global mock hook -- `options(httr2_mock = <fn(req)>)` -- that intercepts every
# req_perform() AND req_perform_promise() call, so the SAME router serves both the
# synchronous and the asynchronous transport with no per-call wiring. (This is why
# we mock at httr2's seam rather than with vcr: async just works.) Connectors set
# this in their hidden knitr setup chunk and their tests, rendering docs and
# running suites against canned, deterministic data -- no network, no credentials,
# no funds.
#
# Every connector previously hand-rolled a near-identical `mock_router`: a
# response builder, a route table, and a dispatch loop. This file is that toolkit,
# generalised to cover all the routing styles the connectors use:
#   * URL-pattern routing (coinbase, alpaca, binance, kucoin) -- a route's `match`
#     is a substring of `req$url`;
#   * body routing (hyperliquid) -- a route's `match` is a predicate that reads the
#     request BODY (the whole REST API sits behind two POST paths discriminated by
#     a body field), expressible with `body_routes()`;
#   * an `httr2_response` PASS-THROUGH (coinbase/alpaca 204 no-content, kucoin's
#     empty pagination page) -- a fixture may return a fully-built response;
#   * STATEFUL fixtures (kucoin pagination) -- a fixture is a thunk invoked per
#     request, so a counter in its closure can return page 1 then the empty page.

# ---- Response builder ----

#' Build a mock `httr2` response from fixture data
#'
#' The single response constructor every mocked route resolves to. It accepts
#' fixture data in three shapes, mirroring how connectors capture fixtures:
#' * an already-built `httr2_response` is returned **unchanged** (the pass-through
#'   path -- e.g. a 204 no-content or a hand-built error response);
#' * a single character string is used **verbatim** as the body (the
#'   real-captured-JSON path -- a fixture file read in as one string);
#' * anything else is JSON-encoded with [jsonlite::toJSON()]
#'   (`auto_unbox = TRUE, null = "null", digits = NA`), matching the live wire.
#'
#' @param body (any) the response body: an `httr2_response` (returned as-is), a
#'   `scalar<character>` (used verbatim), or a list/value (JSON-encoded).
#' @param status (scalar<count in [100, 599]>) the HTTP status code. Default `200`.
#' @param headers (list) the response headers. Default
#'   `list("content-type" = "application/json")`.
#' @return (class<httr2_response>) the mock response.
#' @importFrom httr2 response
#' @export
mock_response <- function(body = NULL, status = 200L, headers = list("content-type" = "application/json")) {
  assert_args_mock_response(body, status, headers)
  if (inherits(body, "httr2_response")) {
    return(body)
  }
  if (is.character(body) && length(body) == 1L) {
    json <- body
  } else {
    json <- as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA))
  }
  return(httr2::response(status_code = status, headers = headers, body = charToRaw(json)))
}

# ---- Request-body access (for body-routed APIs) ----

#' Parse a request's JSON body
#'
#' Reads `req$body$data` and parses it as JSON, returning a list. It copes with
#' every shape httr2 stores a body in: a `raw` vector or a `character` scalar (set
#' by [httr2::req_body_raw()], the byte-verbatim path connectors use to sign the
#' exact body), and an already-deserialised `list` (set by [httr2::req_body_json()],
#' which httr2 serialises only at perform time). Used by body-routed APIs whose
#' endpoint is encoded in the body rather than the URL (e.g. Hyperliquid).
#'
#' @param req (class<httr2_request>) the request whose body to parse.
#' @return (list | NULL) the parsed body, or `NULL` if the request has no body.
#' @export
req_body_json <- function(req) {
  assert_args_req_body_json(req)
  data <- req$body$data
  if (is.null(data)) {
    return(NULL)
  }
  if (is.list(data)) {
    return(data)
  }
  text <- if (is.raw(data)) rawToChar(data) else as.character(data)
  return(jsonlite::fromJSON(text, simplifyVector = FALSE))
}

# ---- Route construction ----

#' A field at a path inside a (possibly nested) list
#'
#' Walks `path` (a character vector of names) into `x`, returning `NULL` if any
#' step is absent. `dig(body, c("action", "type"))` reads `body$action$type`.
#'
#' @keywords internal
#' @noRd
dig <- function(x, path) {
  for (key in path) {
    if (!is.list(x) || is.null(x[[key]])) {
      return(NULL)
    }
    x <- x[[key]]
  }
  return(x)
}

#' Build body-discriminated routes from a named case table
#'
#' The ergonomic constructor for body-routed APIs (e.g. Hyperliquid, whose whole
#' REST surface sits behind two POST paths, each dispatched by a field in the JSON
#' body). Given a URL filter, a body field path, and a **named** list of fixtures
#' keyed by that field's value, it returns one predicate-route per case: each
#' matches when `req$url` contains `url_filter` AND the body field at `field_path`
#' equals that case's name.
#'
#' For example, Hyperliquid's `/info` reads (keyed by `body$type`) and `/exchange`
#' writes (keyed by `body$action$type`) become:
#' ```r
#' mock_router(c(
#'   body_routes("/exchange", c("action", "type"), exchange_routes),
#'   body_routes("/info", "type", info_routes)
#' ))
#' ```
#'
#' @param url_filter (scalar<character>) a substring the request URL must contain.
#' @param field_path (character) the path of names to the discriminating body
#'   field (e.g. `c("action", "type")` for `body$action$type`).
#' @param cases (list) a **named** list of fixtures keyed by the body field's
#'   value; each value is a fixture (a function, a built `httr2_response`, or data).
#' @return (list) a list of routes, one per `names(cases)`, each a
#'   `list(match = <predicate>, fixture = <value>, method = NULL)`.
#' @export
body_routes <- function(url_filter, field_path, cases) {
  assert_args_body_routes(url_filter, field_path, cases)
  routes <- lapply(names(cases), function(name) {
    predicate <- function(req) {
      if (!grepl(url_filter, req$url, fixed = TRUE)) {
        return(FALSE)
      }
      return(identical(as.character(dig(req_body_json(req), field_path)), name))
    }
    return(list(match = predicate, fixture = cases[[name]], method = NULL))
  })
  return(routes)
}

# ---- Router factory ----

#' Build a mock HTTP router (an `httr2` mock hook)
#'
#' A factory returning a `function(req)` suitable for `options(httr2_mock = ...)`.
#' The router walks `routes` in order and returns the first match. A route's
#' matcher is its `match` field if present, else its `pattern` field (the
#' back-compat name the existing connector tables use). The matcher is **either**:
#' * a `scalar<character>` -- matched as a substring of `req$url`
#'   (`grepl(match, req$url, fixed = TRUE)`); the URL-pattern style used by
#'   coinbase, alpaca, binance, and kucoin; **or**
#' * a `function(req) -> logical` -- an arbitrary predicate that may read the URL,
#'   method, AND body, for body-routed APIs (Hyperliquid; see [body_routes()]).
#'
#' A route also carries an optional `method`: if set, the route matches only when
#' `req$method` equals it (so the same URL can map to different fixtures by verb).
#' The matched route's `fixture` is resolved -- called if it is a function, else
#' used as-is -- and passed to `response_builder` (an `httr2_response` is returned
#' unchanged, the pass-through path). Because a fixture is invoked per request, a
#' counter in its closure expresses **stateful** routes (e.g. paginate: page 1
#' then an empty page). An unmatched request raises "Unmocked request".
#'
#' @param routes (list) a list of routes. Each route is a
#'   `list(match = <scalar<character> | function>, fixture = <function | value>,
#'   method = <scalar<character> | NULL>)`. A route may name its matcher `pattern`
#'   instead of `match` (the connectors' existing tables do). (Lists of routes,
#'   e.g. from [body_routes()], can be spliced in with `c()`.)
#' @param response_builder (function) builds a response from resolved fixture data.
#'   Default [mock_response()].
#' @return (function) the dispatcher `function(req)` for `options(httr2_mock = )`.
#' @export
mock_router <- function(routes, response_builder = mock_response) {
  assert_args_mock_router(routes, response_builder)
  dispatch <- function(req) {
    for (route in routes) {
      # Back-compat: the existing connector tables key the URL field `pattern`;
      # `match` is the harness name and wins when both are present.
      matcher <- if (!is.null(route$match)) route$match else route$pattern
      matched <- if (is.function(matcher)) {
        isTRUE(matcher(req))
      } else {
        grepl(matcher, req$url, fixed = TRUE)
      }
      if (!matched) {
        next
      }
      if (!is.null(route$method) && req$method != route$method) {
        next
      }
      value <- if (is.function(route$fixture)) route$fixture() else route$fixture
      if (inherits(value, "httr2_response")) {
        return(value)
      }
      return(response_builder(value))
    }
    stop("Unmocked request: ", req$method, " ", req$url, call. = FALSE)
  }
  return(dispatch)
}

# ---- Scoped activation ----

#' Run code with a mock router installed
#'
#' Installs `mock_router(routes)` as the `httr2_mock` option for the duration of
#' `code`, restoring the previous value afterwards (even on error). This is what a
#' connector's tests and vignettes call instead of hand-setting the option. Every
#' `httr2::req_perform()` / `req_perform_promise()` inside `code` is intercepted.
#'
#' @param routes (list) the routes, as for [mock_router()].
#' @param code (any) the expression to evaluate with the router installed.
#' @return (any) the value of `code`.
#' @noassert
#' @importFrom withr with_options
#' @export
with_mock_api <- function(routes, code) {
  return(withr::with_options(list(httr2_mock = mock_router(routes)), code))
}

#' Install a mock router for the rest of the current scope
#'
#' The [withr::local_options()] companion to [with_mock_api()]: installs
#' `mock_router(routes)` as the `httr2_mock` option until `.env` (the calling
#' frame by default) exits, then restores the previous value. Use it at the top of
#' a `test_that()` block (or any function) to mock every request for the remainder
#' of that scope without nesting the body inside a `code` argument.
#'
#' @param routes (list) the routes, as for [mock_router()].
#' @param .env (class<environment>) the scope whose exit restores the option.
#'   Default [parent.frame()].
#' @return (function) the installed dispatcher, invisibly.
#' @importFrom withr local_options
#' @export
local_mock_api <- function(routes, .env = parent.frame()) {
  assert_args_local_mock_api(routes, .env)
  router <- mock_router(routes)
  withr::local_options(list(httr2_mock = router), .local_envir = .env)
  return(invisible(router))
}

# ---- Fixture loading ----

#' Load JSON fixtures from a directory
#'
#' Reads every `*.json` file in `dir` and returns a **named** list keyed by each
#' file's basename without the extension (`btc_book.json` -> `btc_book`). Each
#' value is the raw JSON string (`parse = FALSE`, the verbatim path that pairs with
#' [mock_response()]'s string-body case) or the parsed list
#' (`parse = TRUE`, via [jsonlite::fromJSON()] with `simplifyVector = FALSE`). This
#' is how a connector loads its real captured fixtures into a route table.
#'
#' @param dir (scalar<character>) a directory holding `*.json` fixture files.
#' @param parse (scalar<logical>) if `TRUE`, parse each file to a list; if `FALSE`
#'   (default), keep the raw JSON string.
#' @return (list) a named list of fixtures (strings or parsed lists), one per
#'   `*.json` file; empty if `dir` holds none.
#' @export
load_fixtures <- function(dir, parse = FALSE) {
  assert_args_load_fixtures(dir, parse)
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  out <- lapply(files, function(path) {
    if (parse) {
      return(jsonlite::fromJSON(path, simplifyVector = FALSE))
    }
    return(paste(readLines(path, warn = FALSE), collapse = "\n"))
  })
  names(out) <- tools::file_path_sans_ext(basename(files))
  return(out)
}
