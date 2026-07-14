# Row-bind a list of records into a data.table

Row-bind a list of records into a data.table

## Usage

``` r
as_dt_list(items)
```

## Arguments

- items:

  (list \| NULL) a list of named lists (a JSON array of objects).

## Value

(class\<data.table\>) the row-bound table (empty if `items` is
`NULL`/empty).
