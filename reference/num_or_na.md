# Coerce a scalar to numeric, or NA

JSON often delivers numbers as strings; this parses one to a double,
returning `NA_real_` for `NULL`, empty, or unparseable input (no
warning).

## Usage

``` r
num_or_na(x)
```

## Arguments

- x:

  (any) a scalar value (number, string, or `NULL`).

## Value

(scalar\<numeric \| NA\>) the parsed double, or `NA_real_`.
