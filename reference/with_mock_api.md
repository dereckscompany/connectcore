# Run code with a mock router installed

Installs `mock_router(routes)` as the `httr2_mock` option for the
duration of `code`, restoring the previous value afterwards (even on
error). This is what a connector's tests and vignettes call instead of
hand-setting the option. Every
[`httr2::req_perform()`](https://httr2.r-lib.org/reference/req_perform.html)
/ `req_perform_promise()` inside `code` is intercepted.

## Usage

``` r
with_mock_api(routes, code)
```

## Arguments

- routes:

  (list) the routes, as for
  [`mock_router()`](https://dereckscompany.github.io/connectcore/reference/mock_router.md).

- code:

  (any) the expression to evaluate with the router installed.

## Value

(any) the value of `code`.
