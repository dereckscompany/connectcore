# Construct a typed WebSocket lifecycle event

Builds the structured event object
[StreamClient](https://dereckscompany.github.io/connectcore/reference/StreamClient.md)
delivers to an `$on_event()` handler: a `list` with an `event_type` (one
of
[WS_EVENT_TYPES](https://dereckscompany.github.io/connectcore/reference/WS_EVENT_TYPES.md)),
a lubridate UTC `timestamp`, and the per-type fields merged in. It is
the WebSocket analogue of the typed REST conditions (see
[`?connectcore_conditions`](https://dereckscompany.github.io/connectcore/reference/connectcore_conditions.md)):
a caller branches on `event$event_type` and reads fields as data instead
of re-parsing a raw callback payload. A WebSocket connector can also
build one directly — e.g. to emit a parsed error frame as a structured
`"error"` event.

## Usage

``` r
ws_event(event_type, fields = list())
```

## Arguments

- event_type:

  (scalar\<character in c("open", "message", "error", "close",
  "reconnect")\>) the event type; also the `event_type` field.

- fields:

  (list) per-type fields merged into the event after `event_type` and
  `timestamp`. Default [`list()`](https://rdrr.io/r/base/list.html).

## Value

(list) the lifecycle event: `event_type`, `timestamp` (POSIXct/UTC),
then the `fields`.

## Details

Per-type fields the base populates: `open` carries `reconnect` (was this
a reconnect); `message` carries `data` (the frame text); `close` carries
`code` and `reason`; `error` carries `error` (the socket error event);
`reconnect` carries `attempt` and `delay` (the backoff seconds).
