# Typed transport conditions and the connector recipe

`connectcore` raises **classed conditions** on transport failures, so a
caller branches on error *type* and reads structured *fields* instead of
regexing the message string. Every condition shares the
`connectcore_error` root, and each failure surface adds a more specific
class in front of it. The classes are additive: the message string and
the `rlang_error` / `error` / `condition` parents are unchanged, so
nothing that matched on message text before breaks.

## Details

### Class taxonomy

|  |  |  |  |
|----|----|----|----|
| Raiser | Most specific class | Fields | Raised when |
| [`abort_api_error()`](https://dereckscompany.github.io/connectcore/reference/abort_api_error.md) | `connectcore_api_error_<status>` | `status`, `url`, `body_snippet` | non-2xx HTTP status |
| [`abort_response_error()`](https://dereckscompany.github.io/connectcore/reference/abort_response_error.md) | `connectcore_response_error` | `field`, `url`, `body_snippet` | malformed body |
| [`abort_stream_error()`](https://dereckscompany.github.io/connectcore/reference/abort_stream_error.md) | `connectcore_stream_error` | `url` | `StreamClient` transport failure |

The response-body field is `body_snippet` (not `body`) because
[`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html)
reserves `body` for its own message formatting; a field named `body`
would be rendered into the message instead of stored. Read it as
`e$body_snippet`.

Every class above nests under the shared roots, ordered specific -\>
general. An API error's full vector is
`c("connectcore_api_error_<status>",`
`"connectcore_api_error", "connectcore_error", "rlang_error", "error",`
`"condition")`; the response and stream errors are the same minus the
HTTP family layers (`connectcore_response_error` /
`connectcore_stream_error`, then `connectcore_error`, then rlang's
classes).

The per-status class (`connectcore_api_error_429`,
`connectcore_api_error_401`, ...) lets a caller catch one status without
catching the rest; the `connectcore_api_error` family class catches
every HTTP failure; the `connectcore_error` root catches every transport
failure of any kind.

[`abort_api_error()`](https://dereckscompany.github.io/connectcore/reference/abort_api_error.md)
is the default
[`parse_json_response()`](https://dereckscompany.github.io/connectcore/reference/parse_json_response.md)
envelope, so a connector that keeps the default HTTP-status parser
inherits it for free;
[`abort_response_error()`](https://dereckscompany.github.io/connectcore/reference/abort_response_error.md)
covers a parsed-but-malformed body (e.g.
[`fetch_server_time_ms()`](https://dereckscompany.github.io/connectcore/reference/fetch_server_time_ms.md));
[`abort_stream_error()`](https://dereckscompany.github.io/connectcore/reference/abort_stream_error.md)
covers a
[StreamClient](https://dereckscompany.github.io/connectcore/reference/StreamClient.md)
transport failure (e.g. `$send()` on a closed socket).

### Reacting by type

    tryCatch(
      client$get_order(id),
      connectcore_api_error_429 = function(e) {
        Sys.sleep(retry_after(e)) # e$status is 429; read it, don't grep it
        retry()
      },
      connectcore_api_error_401 = function(e) refresh_auth_and_retry(),
      connectcore_api_error = function(e) log_failure(status = e$status, url = e$url),
      connectcore_error = function(e) bail(e)
    )

`url` is stored with query-string credentials redacted (see
[`abort_api_error()`](https://dereckscompany.github.io/connectcore/reference/abort_api_error.md)),
so logging `e$url` never leaks a secret; `e$body_snippet` is a
truncated, log-safe slice of the response body.

### Recipe: a connector subclasses these

A connector with its own error envelope (a `code` / `msg` field that
signals failure on an HTTP 200, or a venue-specific error surface)
raises its **own** class IN FRONT of the connectcore class, so a venue
error still catches under the shared roots. Define a thin raiser in the
connector and wire it into the connector's `parse_envelope`:

    # In package `binance`, R/conditions.R
    abort_binance_error <- function(status, code, msg, url = NULL, body = NULL) {
      return(rlang::abort(
        message = paste0("Binance error ", code, ": ", msg),
        class = c(
          sprintf("binance_api_error_%d", as.integer(status)),
          "binance_api_error",
          # ...then the connectcore family, so `connectcore_api_error` still catches it:
          sprintf("connectcore_api_error_%d", as.integer(status)),
          "connectcore_api_error",
          "connectcore_error"
        ),
        status = as.integer(status), code = code,
        url = connectcore::scrub_url(url),
        # Store the body under `body_snippet`, NOT `body`: rlang::abort() reserves
        # `body` for message formatting, so a `body =` field is swallowed.
        body_snippet = body,
        call = rlang::caller_env()
      ))
    }

A caller can then catch `binance_api_error` (venue-specific) OR
`connectcore_api_error` (any HTTP failure across the fleet) OR
`connectcore_error` (any transport failure) — whichever granularity it
wants. For a connector that keeps the default HTTP-status envelope, no
work is needed: it inherits
[`abort_api_error()`](https://dereckscompany.github.io/connectcore/reference/abort_api_error.md)
through
[`parse_json_response()`](https://dereckscompany.github.io/connectcore/reference/parse_json_response.md)
for free.

## See also

[`abort_api_error()`](https://dereckscompany.github.io/connectcore/reference/abort_api_error.md),
[`abort_response_error()`](https://dereckscompany.github.io/connectcore/reference/abort_response_error.md),
[`abort_stream_error()`](https://dereckscompany.github.io/connectcore/reference/abort_stream_error.md)
