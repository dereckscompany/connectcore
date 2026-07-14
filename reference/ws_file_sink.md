# A message handler that appends each frame to a connection

Convenience for the recorder hot path: returns a `"message"` handler
that writes each frame followed by a newline to an open connection,
doing the absolute minimum so the socket is drained fast (a slow handler
can get a connection dropped by the server). Hourly rotation / flushing
is the caller's job — pass a connection you
[`flush()`](https://rdrr.io/r/base/connections.html) and rotate
yourself.

## Usage

``` r
ws_file_sink(con)
```

## Arguments

- con:

  (class\<connection\>) an open, writable connection (e.g. from
  [`base::file()`](https://rdrr.io/r/base/connections.html) in append
  mode).

## Value

(function) a handler `function(message)` suitable for
`StreamClient$on("message", ...)`.
