# Convert an epoch value to POSIXct (UTC)

Convert an epoch value to POSIXct (UTC)

## Usage

``` r
epoch_to_datetime(value, unit = c("ms", "ns", "s"))
```

## Arguments

- value:

  (numeric) epoch time.

- unit:

  (scalar\<character in c("ms", "ns", "s")\>) the input unit:
  milliseconds (default), nanoseconds, or seconds.

## Value

(class\<POSIXct\>) the time in UTC.
