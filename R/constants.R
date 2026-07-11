# File: R/constants.R
# Exported constants for connectcore.

#' @title WebSocket Events
#' @description The standard events [StreamClient] emits to the string-keyed
#' `$on(event, handler)` registry. A subclass' `.dispatch()` may emit additional,
#' connector-specific names (e.g. one per message type); these are the ones the
#' base guarantees. Reference them as e.g. `WS_EVENTS$MESSAGE`.
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

#' @title WebSocket Lifecycle Event Types
#' @description The `event_type` values a typed lifecycle event carries (see
#' [ws_event] and `StreamClient$on_event()`). This is the parallel, structured
#' surface to [WS_EVENTS]: `WS_EVENTS` names the string-keyed callbacks a caller
#' registers with `$on()`; `WS_EVENT_TYPES` names the `event_type` field on the
#' single typed object delivered to `$on_event()`. Downstream connectors branch on
#' `event$event_type == WS_EVENT_TYPES$CLOSE` rather than a bare literal. Reference
#' them as e.g. `WS_EVENT_TYPES$CLOSE`.
#' @export
WS_EVENT_TYPES <- list(
  OPEN = "open",
  MESSAGE = "message",
  ERROR = "error",
  CLOSE = "close",
  RECONNECT = "reconnect"
)
