# File: R/constants.R
# Exported constants for connectcore.

#' Standard WebSocket event names
#'
#' The core events [StreamClient] emits. A subclass' `.dispatch()` may emit
#' additional, connector-specific names (e.g. one per message type); these are
#' the ones the base guarantees.
#'
#' @return (character) the standard event names.
#' @export
ws_events <- function() {
  return(c(
    "open", "message", "close", "error",
    "reconnecting", "reconnected", "giveup", "stale"
  ))
}
