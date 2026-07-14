# Convert epoch milliseconds to POSIXct (UTC)

The fleet-wide convenience for the common measurement-time case:
connectors feed it a raw JSON timestamp field whose R type is not known
ahead of time (numeric, character, or an all-`NA` logical when every
record was empty). It is length-preserving and NA-in -\> NA-out, so an
all-`NA` input still yields a POSIXct vector of the same length
(suitable for
[`coerce_cols()`](https://dereckscompany.github.io/connectcore/reference/coerce_cols.md)
on a column documented as POSIXct — a scalar `NA` would be recycled into
the column's existing storage type rather than replacing it with a
POSIXct one).

## Usage

``` r
ms_to_datetime(ms)
```

## Arguments

- ms:

  (any \| NULL) epoch millisecond timestamp(s); the raw JSON value,
  whose R type is unconstrained (numeric, character, or an all-`NA`
  logical).

## Value

(class\<POSIXct\>) a POSIXct vector in UTC (length matching `ms`), `NA`
where `ms` is `NULL`/`NA`.
