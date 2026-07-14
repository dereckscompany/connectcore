# Collapse plain-string array fields to semicolon-joined scalars

Replaces each named field holding an array of short strings with one
`;`-joined character scalar, so a record stays one row with no list
columns. `;` is used (not `,`) because the values are short
codes/identifiers; recover the vector with
`strsplit(value, ";", fixed = TRUE)`. Empty/missing arrays become
`NA_character_`. A once-per-session warning fires if a value already
contains a `;` (which a later split would corrupt).

## Usage

``` r
collapse_string_array_fields(x, fields)
```

## Arguments

- x:

  (list) a named list (one record).

- fields:

  (character) names of the fields to collapse.

## Value

(list) the same record with those fields collapsed in place.
