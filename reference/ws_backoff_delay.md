# Full-jitter exponential reconnect backoff (seconds)

Returns a randomised delay that grows as `2^attempt` but is capped, so a
flood of reconnect attempts can never trip a server's connection rate
limit. The jitter (a uniform `[0, 1)` factor) de-synchronises many
clients reconnecting at once, and the `+1` floor guarantees a minimum
spacing.

## Usage

``` r
ws_backoff_delay(attempt, cap_seconds = 60)
```

## Arguments

- attempt:

  (scalar\<count in \[1, Inf\[\>) the reconnect attempt number (1, 2, 3,
  ...).

- cap_seconds:

  (scalar\<numeric in \]0, Inf\[\>) maximum delay before the jitter
  floor. Default `60`.

## Value

(scalar\<numeric in \[1, Inf\[\>) a delay in seconds, always `>= 1`.
