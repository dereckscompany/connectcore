# Convert a named list to a one-row data.table

Turns a flat named list (one JSON object) into a single-row
[data.table::data.table](https://rdrr.io/pkg/data.table/man/data.table.html):
`NULL` becomes `NA`, names are snake_cased, and any nested value is
wrapped as a single list-column cell so the row never widens
unexpectedly (per-endpoint parsers flatten nesting themselves).

## Usage

``` r
as_dt_row(x)
```

## Arguments

- x:

  (list \| NULL) a named list (one record).

## Value

(class\<data.table\>) a one-row data.table (empty if `x` is
`NULL`/empty).
