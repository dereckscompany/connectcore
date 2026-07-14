# First non-NULL value

First non-NULL value

## Usage

``` r
coalesce_null(x, default = NA)
```

## Arguments

- x:

  (any) a value, possibly `NULL`.

- default:

  (any) returned when `x` is `NULL`.

## Value

(any) `x` if not `NULL`, else `default`.
