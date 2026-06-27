# File: R/constants.R
# Exported constants for connectcore.

#' @title WebSocket Events
#' @description The standard events [StreamClient] emits. A subclass' `.dispatch()`
#' may emit additional, connector-specific names (e.g. one per message type);
#' these are the ones the base guarantees. Reference them as e.g.
#' `WS_EVENTS$MESSAGE`.
#' @export
WS_EVENTS <- list(
  OPEN = "open",
  MESSAGE = "message",
  CLOSE = "close",
  ERROR = "error",
  RECONNECTING = "reconnecting",
  RECONNECTED = "reconnected",
  GIVEUP = "giveup",
  STALE = "stale"
)
