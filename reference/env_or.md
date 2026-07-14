# Read an environment variable with a default

Read an environment variable with a default

## Usage

``` r
env_or(var, default = "")
```

## Arguments

- var:

  (scalar\<character\>) the environment variable name.

- default:

  (scalar\<character\>) returned when the variable is unset/empty.
  Default `""`.

## Value

(scalar\<character\>) the variable's value, or `default`.
