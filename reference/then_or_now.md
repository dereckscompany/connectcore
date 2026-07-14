# Apply a continuation to a value or a promise

The single sync/async branching point. Routes a value through `fn`
either synchronously or as a
[promises::promise](https://rstudio.github.io/promises/reference/promise.html),
depending on `is_async`. A connector writes its methods
mode-agnostically and only chooses `is_async` once.

## Usage

``` r
then_or_now(x, fn, is_async = FALSE)
```

## Arguments

- x:

  (any) a value, or a
  [promises::promise](https://rstudio.github.io/promises/reference/promise.html)
  resolving to one.

- fn:

  (function) applied to the (resolved) value of `x`.

- is_async:

  (scalar\<logical\>) if `TRUE`, return `promises::then(x, fn)`;
  otherwise return `fn(x)`. Default `FALSE`.

## Value

(any) `fn(x)`, or a promise resolving to it.
