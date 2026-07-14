# Next monotonic nonce (epoch milliseconds, strictly increasing)

Returns `max(previous + 1, now_ms)`, so successive calls strictly
increase even within the same millisecond. Some signed APIs require a
strictly-monotonic nonce per credential to reject replays.

## Usage

``` r
next_nonce()
```

## Value

(scalar\<numeric\>) a strictly increasing epoch-millisecond nonce.
