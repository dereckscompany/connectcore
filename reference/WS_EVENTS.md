# WebSocket Events

The standard events
[StreamClient](https://dereckscompany.github.io/connectcore/reference/StreamClient.md)
emits to the string-keyed `$on(event, handler)` registry. A subclass'
`.dispatch()` may emit additional, connector-specific names (e.g. one
per message type); these are the ones the base guarantees. Reference
them as e.g. `WS_EVENTS$MESSAGE`.

## Usage

``` r
WS_EVENTS
```

## Format

An object of class `list` of length 8.
