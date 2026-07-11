# File: R/conditions.R
# Typed conditions for the transport base. Every transport failure signals a
# classed condition ordered specific -> general, layered on top of rlang's error
# classes, and carrying structured fields a caller reads instead of grepping the
# message text. connectcore is the base every connector extends, so a condition
# raised here is inherited fleet-wide; a connector layers its own <pkg>_api_error
# IN FRONT of these classes (see the recipe in `?connectcore_conditions`).
#
# Backward compatibility is a hard contract: each raiser signals the SAME message
# string the bare `rlang::abort()` at its call site signalled before, so existing
# tests and downstream message greps keep matching. The classes and the fields
# are purely additive.

#' Typed transport conditions and the connector recipe
#'
#' `connectcore` raises **classed conditions** on transport failures, so a caller
#' branches on error *type* and reads structured *fields* instead of regexing the
#' message string. Every condition shares the `connectcore_error` root, and each
#' failure surface adds a more specific class in front of it. The classes are
#' additive: the message string and the `rlang_error` / `error` / `condition`
#' parents are unchanged, so nothing that matched on message text before breaks.
#'
#' ### Class taxonomy
#'
#' | Raiser | Most specific class | Fields | Raised when |
#' | --- | --- | --- | --- |
#' | [abort_api_error()] | `connectcore_api_error_<status>` | `status`, `url`, `body_snippet` | non-2xx HTTP status |
#' | [abort_response_error()] | `connectcore_response_error` | `field`, `url`, `body_snippet` | malformed body |
#' | [abort_stream_error()] | `connectcore_stream_error` | `url` | `StreamClient` transport failure |
#'
#' The response-body field is `body_snippet` (not `body`) because `rlang::abort()`
#' reserves `body` for its own message formatting; a field named `body` would be
#' rendered into the message instead of stored. Read it as `e$body_snippet`.
#'
#' Every class above nests under the shared roots, ordered specific -> general.
#' An API error's full vector is `c("connectcore_api_error_<status>",`
#' `"connectcore_api_error", "connectcore_error", "rlang_error", "error",`
#' `"condition")`; the response and stream errors are the same minus the HTTP
#' family layers (`connectcore_response_error` / `connectcore_stream_error`, then
#' `connectcore_error`, then rlang's classes).
#'
#' The per-status class (`connectcore_api_error_429`, `connectcore_api_error_401`,
#' ...) lets a caller catch one status without catching the rest; the
#' `connectcore_api_error` family class catches every HTTP failure; the
#' `connectcore_error` root catches every transport failure of any kind.
#'
#' `abort_api_error()` is the default `parse_json_response()` envelope, so a
#' connector that keeps the default HTTP-status parser inherits it for free;
#' `abort_response_error()` covers a parsed-but-malformed body (e.g.
#' [fetch_server_time_ms()]); `abort_stream_error()` covers a [StreamClient]
#' transport failure (e.g. `$send()` on a closed socket).
#'
#' ### Reacting by type
#'
#' ```r
#' tryCatch(
#'   client$get_order(id),
#'   connectcore_api_error_429 = function(e) {
#'     Sys.sleep(retry_after(e)) # e$status is 429; read it, don't grep it
#'     retry()
#'   },
#'   connectcore_api_error_401 = function(e) refresh_auth_and_retry(),
#'   connectcore_api_error = function(e) log_failure(status = e$status, url = e$url),
#'   connectcore_error = function(e) bail(e)
#' )
#' ```
#'
#' `url` is stored with query-string credentials redacted (see [abort_api_error()]),
#' so logging `e$url` never leaks a secret; `e$body_snippet` is a truncated,
#' log-safe slice of the response body.
#'
#' ### Recipe: a connector subclasses these
#'
#' A connector with its own error envelope (a `code` / `msg` field that signals
#' failure on an HTTP 200, or a venue-specific error surface) raises its **own**
#' class IN FRONT of the connectcore class, so a venue error still catches under
#' the shared roots. Define a thin raiser in the connector and wire it into the
#' connector's `parse_envelope`:
#'
#' ```r
#' # In package `binance`, R/conditions.R
#' abort_binance_error <- function(status, code, msg, url = NULL, body = NULL) {
#'   return(rlang::abort(
#'     message = paste0("Binance error ", code, ": ", msg),
#'     class = c(
#'       sprintf("binance_api_error_%d", as.integer(status)),
#'       "binance_api_error",
#'       # ...then the connectcore family, so `connectcore_api_error` still catches it:
#'       sprintf("connectcore_api_error_%d", as.integer(status)),
#'       "connectcore_api_error",
#'       "connectcore_error"
#'     ),
#'     status = as.integer(status), code = code,
#'     url = connectcore::scrub_url(url),
#'     # Store the body under `body_snippet`, NOT `body`: rlang::abort() reserves
#'     # `body` for message formatting, so a `body =` field is swallowed.
#'     body_snippet = body,
#'     call = rlang::caller_env()
#'   ))
#' }
#' ```
#'
#' A caller can then catch `binance_api_error` (venue-specific) OR
#' `connectcore_api_error` (any HTTP failure across the fleet) OR
#' `connectcore_error` (any transport failure) — whichever granularity it wants.
#' For a connector that keeps the default HTTP-status envelope, no work is needed:
#' it inherits [abort_api_error()] through [parse_json_response()] for free.
#'
#' @seealso [abort_api_error()], [abort_response_error()], [abort_stream_error()]
#' @name connectcore_conditions
NULL

#' Redact query-string credentials from a URL
#'
#' Returns `url` with the *value* of every query parameter whose name contains a
#' sensitive token (case-insensitively) replaced by `<redacted>`, so a URL stored
#' on a condition or written to a log never leaks a signature, API key, or token.
#' The path and the non-sensitive parameters (symbol, limit, ...) are preserved
#' for debugging. Matching is deliberately conservative: a substring match on the
#' key over-redacts a borderline name rather than risk leaking a secret.
#'
#' @param url (scalar<character> | NULL) a URL, possibly carrying a query string.
#'   `NULL` returns `NULL`.
#' @param sensitive_params (vector<character, 1..>) parameter-name tokens whose
#'   values are redacted (matched as a case-insensitive substring of the key).
#' @return (scalar<character> | NULL) the URL with sensitive query values redacted.
#' @seealso [connectcore_conditions]
#' @export
scrub_url <- function(
  url,
  sensitive_params = c(
    "key",
    "secret",
    "sign",
    "signature",
    "sig",
    "token",
    "pass",
    "passphrase",
    "apikey",
    "api_key",
    "access",
    "nonce"
  )
) {
  assert_args_scrub_url(url, sensitive_params)
  out <- url
  if (!is.null(url) && length(url) == 1L && !is.na(url)) {
    parts <- strsplit(url, "?", fixed = TRUE)[[1]]
    if (length(parts) >= 2L) {
      base <- parts[1L]
      query <- paste(parts[-1L], collapse = "?")
      pairs <- strsplit(query, "&", fixed = TRUE)[[1]]
      redacted <- vapply(
        pairs,
        function(pair) {
          kv <- strsplit(pair, "=", fixed = TRUE)[[1]]
          key <- kv[1L]
          out_pair <- pair
          if (length(kv) >= 2L && .is_sensitive_param(key, sensitive_params)) {
            out_pair <- paste0(key, "=<redacted>")
          }
          return(out_pair)
        },
        character(1),
        USE.NAMES = FALSE
      )
      out <- paste0(base, "?", paste(redacted, collapse = "&"))
    }
  }
  return(assert_return_scrub_url(out))
}

#' Does a query-parameter key contain any sensitive token (case-insensitively)?
#' @keywords internal
#' @noRd
.is_sensitive_param <- function(key, sensitive_params) {
  key_lower <- tolower(key)
  hit <- vapply(
    sensitive_params,
    function(token) grepl(token, key_lower, fixed = TRUE),
    logical(1),
    USE.NAMES = FALSE
  )
  return(any(hit))
}

#' Truncate a body snippet to a sane length for storage on a condition, so a
#' multi-megabyte error page never bloats the condition object or a log line.
#' @keywords internal
#' @noRd
.truncate_body <- function(body, max_chars) {
  out <- body
  if (!is.null(body) && length(body) == 1L && !is.na(body) && nchar(body) > max_chars) {
    out <- paste0(substr(body, 1L, max_chars), "... <truncated>")
  }
  return(out)
}

#' Raise a typed HTTP API error
#'
#' Signals a condition classed `c("connectcore_api_error_<status>",`
#' `"connectcore_api_error", "connectcore_error")` (on top of rlang's error
#' classes), carrying the HTTP `status`, the request `url` (query-string
#' credentials redacted), and a truncated `body_snippet` as structured fields. The
#' message defaults to the byte-identical `"HTTP error <status>\n<body>"` the
#' transport base signalled before typed conditions existed, so nothing that
#' matched on message text breaks. See [connectcore_conditions] for the taxonomy
#' and the connector-subclass recipe.
#'
#' @param status (scalar<count in [100, 599]>) the HTTP status code. Also names
#'   the most specific class, `connectcore_api_error_<status>`.
#' @param url (scalar<character> | NULL) the request URL; query-string credentials
#'   are redacted with [scrub_url()] before storing on the `url` field. Default
#'   `NULL`.
#' @param body (scalar<character> | NULL) the response body text; stored truncated
#'   to `max_body` characters on the `body_snippet` field (named `body_snippet`,
#'   not `body`, because `rlang::abort()` reserves `body`). Default `NULL`.
#' @param message (scalar<character> | NULL) the condition message. `NULL`
#'   (default) derives the byte-identical legacy string from `status` and `body`.
#' @param max_body (scalar<count in [1, Inf[>) truncate the stored body snippet
#'   to this many characters. Default `2048`.
#' @return (class<connectcore_error>) never returns normally; signals the classed
#'   condition described above.
#' @importFrom rlang abort caller_env
#' @seealso [connectcore_conditions]
#' @noassert
#' @export
abort_api_error <- function(status, url = NULL, body = NULL, message = NULL, max_body = 2048L) {
  if (is.null(message)) {
    message <- paste0("HTTP error ", status)
    if (!is.null(body)) {
      message <- paste0(message, "\n", body)
    }
  }
  return(rlang::abort(
    message = message,
    class = c(
      sprintf("connectcore_api_error_%d", as.integer(status)),
      "connectcore_api_error",
      "connectcore_error"
    ),
    status = as.integer(status),
    url = scrub_url(url),
    body_snippet = .truncate_body(body, max_body),
    call = rlang::caller_env()
  ))
}

#' Raise a typed response-parse error
#'
#' Signals a condition classed `c("connectcore_response_error",`
#' `"connectcore_error")` for a response that reached the client but is malformed
#' or missing an expected field (e.g. a server-time endpoint whose payload lacks
#' its time key). Carries the offending `field`, the request `url` (credentials
#' redacted), and a truncated `body` snippet. The `message` is passed through
#' verbatim, so an existing string stays byte-identical. See
#' [connectcore_conditions] for the taxonomy.
#'
#' @param message (scalar<character>) the condition message (passed through
#'   verbatim).
#' @param field (scalar<character> | NULL) the missing / malformed field name, if
#'   known. Default `NULL`.
#' @param url (scalar<character> | NULL) the request URL; query-string credentials
#'   are redacted with [scrub_url()] before storing on the `url` field. Default
#'   `NULL`.
#' @param body (scalar<character> | NULL) the response body text; stored truncated
#'   to `max_body` characters on the `body_snippet` field (named `body_snippet`,
#'   not `body`, because `rlang::abort()` reserves `body`). Default `NULL`.
#' @param max_body (scalar<count in [1, Inf[>) truncate the stored body snippet
#'   to this many characters. Default `2048`.
#' @return (class<connectcore_error>) never returns normally; signals the classed
#'   condition described above.
#' @importFrom rlang abort caller_env
#' @seealso [connectcore_conditions]
#' @noassert
#' @export
abort_response_error <- function(message, field = NULL, url = NULL, body = NULL, max_body = 2048L) {
  return(rlang::abort(
    message = message,
    class = c("connectcore_response_error", "connectcore_error"),
    field = field,
    url = scrub_url(url),
    body_snippet = .truncate_body(body, max_body),
    call = rlang::caller_env()
  ))
}

#' Raise a typed stream error
#'
#' Signals a condition classed `c("connectcore_stream_error",`
#' `"connectcore_error")` for a [StreamClient] transport failure (e.g. calling
#' `$send()` while the socket is closed). Carries the socket `url` (credentials
#' redacted) when available. The `message` is passed through verbatim, so an
#' existing string stays byte-identical. See [connectcore_conditions] for the
#' taxonomy.
#'
#' @param message (scalar<character>) the condition message (passed through
#'   verbatim).
#' @param url (scalar<character> | NULL) the socket URL; query-string credentials
#'   are redacted with [scrub_url()] before storing. Default `NULL`.
#' @return (class<connectcore_error>) never returns normally; signals the classed
#'   condition described above.
#' @importFrom rlang abort caller_env
#' @seealso [connectcore_conditions]
#' @noassert
#' @export
abort_stream_error <- function(message, url = NULL) {
  return(rlang::abort(
    message = message,
    class = c("connectcore_stream_error", "connectcore_error"),
    url = scrub_url(url),
    call = rlang::caller_env()
  ))
}
