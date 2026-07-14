# Install a mock router for the rest of the current scope

The
[`withr::local_options()`](https://withr.r-lib.org/reference/with_options.html)
companion to
[`with_mock_api()`](https://dereckscompany.github.io/connectcore/reference/with_mock_api.md):
installs `mock_router(routes)` as the `httr2_mock` option until `.env`
(the calling frame by default) exits, then restores the previous value.
Use it at the top of a `test_that()` block (or any function) to mock
every request for the remainder of that scope without nesting the body
inside a `code` argument.

## Usage

``` r
local_mock_api(routes, .env = parent.frame())
```

## Arguments

- routes:

  (list) the routes, as for
  [`mock_router()`](https://dereckscompany.github.io/connectcore/reference/mock_router.md).

- .env:

  (class\<environment\>) the scope whose exit restores the option.
  Default [`parent.frame()`](https://rdrr.io/r/base/sys.parent.html).

## Value

(function) the installed dispatcher, invisibly.
