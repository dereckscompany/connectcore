# Convert POSIXct to an epoch value

Convert POSIXct to an epoch value

## Usage

``` r
datetime_to_epoch(datetime, unit = c("ms", "ns", "s"))
```

## Arguments

- datetime:

  (class\<POSIXct\>) the time to convert.

- unit:

  (scalar\<character in c("ms", "ns", "s")\>) the output unit:
  milliseconds (default), nanoseconds, or seconds.

## Value

(numeric) the epoch value in `unit` (a double; ms/ns exceed int range).
