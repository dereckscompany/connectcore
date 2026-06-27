# File: R/helpers_ws.R
# Pure, connection-free helpers for the WebSocket stream client. Unit-testable in
# isolation and — like the public methods — typed and asserted via roxyassert.

#' Full-jitter exponential reconnect backoff (seconds)
#'
#' Returns a randomised delay that grows as `2^attempt` but is capped, so a flood
#' of reconnect attempts can never trip a server's connection rate limit. The
#' jitter (a uniform `[0, 1)` factor) de-synchronises many clients reconnecting at
#' once, and the `+1` floor guarantees a minimum spacing.
#'
#' @param attempt (scalar<count in [1, Inf[>) the reconnect attempt number
#'   (1, 2, 3, ...).
#' @param cap_seconds (scalar<numeric in ]0, Inf[>) maximum delay before the jitter
#'   floor. Default `60`.
#' @return (scalar<numeric in [1, Inf[>) a delay in seconds, always `>= 1`.
#' @importFrom stats runif
#' @export
ws_backoff_delay <- function(attempt, cap_seconds = 60) {
  assert_args_ws_backoff_delay(attempt, cap_seconds)
  expo <- 2^attempt - 1
  return(assert_return_ws_backoff_delay(round(stats::runif(1) * min(cap_seconds, expo) + 1)))
}

#' A message handler that appends each frame to a connection
#'
#' Convenience for the recorder hot path: returns a `"message"` handler that
#' writes each frame followed by a newline to an open connection, doing the
#' absolute minimum so the socket is drained fast (a slow handler can get a
#' connection dropped by the server). Hourly rotation / flushing is the caller's
#' job — pass a connection you `flush()` and rotate yourself.
#'
#' @param con (class<connection>) an open, writable connection (e.g. from
#'   [base::file()] in append mode).
#' @return (function) a handler `function(message)` suitable for
#'   `StreamClient$on("message", ...)`.
#' @export
ws_file_sink <- function(con) {
  assert_args_ws_file_sink(con)
  handler <- function(message) {
    cat(message, "\n", file = con, sep = "")
    return(invisible(NULL))
  }
  return(assert_return_ws_file_sink(handler))
}
