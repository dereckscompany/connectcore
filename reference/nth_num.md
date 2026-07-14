# The nth element of a positional array as numeric (or NA)

For array-shaped records (e.g. a kline `[open_time, open, high, ...]`).

## Usage

``` r
nth_num(x, i)
```

## Arguments

- x:

  (list) a positional array.

- i:

  (scalar\<count in \[1, Inf\[\>) the 1-based index.

## Value

(scalar\<numeric \| NA\>) the element as a double, or `NA_real_`.
