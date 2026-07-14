# WebSocket Lifecycle Event Types

The `event_type` values a typed lifecycle event carries (see
[ws_event](https://dereckscompany.github.io/connectcore/reference/ws_event.md)
and `StreamClient$on_event()`). This is the parallel, structured surface
to
[WS_EVENTS](https://dereckscompany.github.io/connectcore/reference/WS_EVENTS.md):
`WS_EVENTS` names the string-keyed callbacks a caller registers with
`$on()`; `WS_EVENT_TYPES` names the `event_type` field on the single
typed object delivered to `$on_event()`. Downstream connectors branch on
`event$event_type == WS_EVENT_TYPES$CLOSE` rather than a bare literal.
Reference them as e.g. `WS_EVENT_TYPES$CLOSE`.

## Usage

``` r
WS_EVENT_TYPES
```

## Format

An object of class `list` of length 5.
