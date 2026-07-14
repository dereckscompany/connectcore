# Coerce columns of a data.table in place

Applies `fn` to each named column by reference (via data.table::set);
columns not present are skipped. Typically used to turn epoch columns
into POSIXct or string columns into numeric after a generic parse.

## Usage

``` r
coerce_cols(dt, cols, fn)
```

## Arguments

- dt:

  (class\<data.table\>) the table to mutate (by reference).

- cols:

  (character) column names to coerce (missing ones are ignored).

- fn:

  (function) applied to each column vector.

## Value

(class\<data.table\>) `dt`, invisibly, after coercion.
