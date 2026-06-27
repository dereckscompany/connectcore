# File: R/helpers_parse.R
# Generic JSON -> data.table coercion toolkit. These turn parsed JSON (lists)
# into flat data.tables with snake_case columns and no list columns. They carry
# no venue semantics; per-endpoint parsers build on them. Shared verbatim across
# connectors (the convention was already duplicated in binance/alpaca/kucoin).

#' Convert camelCase names to snake_case
#'
#' @param names (character) names to convert.
#' @return (character) the snake_case names.
#' @export
to_snake_case <- function(names) {
  out <- gsub("([a-z0-9])([A-Z])", "\\1_\\2", names)
  out <- gsub("([A-Z])([A-Z][a-z])", "\\1_\\2", out)
  return(tolower(out))
}

#' First non-NULL value
#'
#' @param x (any) a value, possibly `NULL`.
#' @param default (any) returned when `x` is `NULL`.
#' @return (any) `x` if not `NULL`, else `default`.
#' @export
coalesce_null <- function(x, default = NA) {
  if (is.null(x)) {
    return(default)
  }
  return(x)
}

#' Coerce a scalar to numeric, or NA
#'
#' JSON often delivers numbers as strings; this parses one to a double, returning
#' `NA_real_` for `NULL`, empty, or unparseable input (no warning).
#'
#' @param x (any) a scalar value (number, string, or `NULL`).
#' @return (scalar<numeric | NA>) the parsed double, or `NA_real_`.
#' @export
num_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_real_)
  }
  return(suppressWarnings(as.numeric(x[[1L]])))
}

#' Coerce a scalar to character, or NA
#'
#' @param x (any) a scalar value, or `NULL`.
#' @return (scalar<character | NA>) the value as a string, or `NA_character_`.
#' @export
chr_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_character_)
  }
  return(as.character(x[[1L]]))
}

#' Coerce a scalar to logical, or NA
#'
#' @param x (any) a scalar value, or `NULL`.
#' @return (scalar<logical | NA>) the value as a logical, or `NA`.
#' @export
lgl_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA)
  }
  return(as.logical(x[[1L]]))
}

#' The nth element of a positional array as numeric (or NA)
#'
#' For array-shaped records (e.g. a kline `[open_time, open, high, ...]`).
#'
#' @param x (list) a positional array.
#' @param i (scalar<count in [1, Inf[>) the 1-based index.
#' @return (scalar<numeric | NA>) the element as a double, or `NA_real_`.
#' @export
nth_num <- function(x, i) {
  if (is.null(x) || length(x) < i) {
    return(NA_real_)
  }
  return(num_or_na(x[[i]]))
}

#' The nth element of a positional array as character (or NA)
#'
#' @param x (list) a positional array.
#' @param i (scalar<count in [1, Inf[>) the 1-based index.
#' @return (scalar<character | NA>) the element as a string, or `NA_character_`.
#' @export
nth_chr <- function(x, i) {
  if (is.null(x) || length(x) < i) {
    return(NA_character_)
  }
  return(chr_or_na(x[[i]]))
}

#' Convert a named list to a one-row data.table
#'
#' Turns a flat named list (one JSON object) into a single-row
#' [data.table::data.table]: `NULL` becomes `NA`, names are snake_cased, and any
#' nested value is wrapped as a single list-column cell so the row never widens
#' unexpectedly (per-endpoint parsers flatten nesting themselves).
#'
#' @param x (list | NULL) a named list (one record).
#' @return (class<data.table>) a one-row data.table (empty if `x` is `NULL`/empty).
#' @importFrom data.table as.data.table setnames
#' @export
as_dt_row <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(data.table::data.table()[])
  }
  x <- lapply(x, function(val) {
    if (is.null(val)) {
      return(NA)
    }
    if (is.list(val) && length(val) == 0L) {
      return(NA)
    }
    if (is.list(val) && length(val) >= 1L) {
      return(list(val))
    }
    return(val)
  })
  dt <- data.table::as.data.table(x)
  data.table::setnames(dt, to_snake_case(names(dt)))
  return(dt[])
}

#' Row-bind a list of records into a data.table
#'
#' @param items (list | NULL) a list of named lists (a JSON array of objects).
#' @return (class<data.table>) the row-bound table (empty if `items` is
#'   `NULL`/empty).
#' @importFrom data.table rbindlist
#' @export
as_dt_list <- function(items) {
  if (is.null(items) || length(items) == 0L) {
    return(data.table::data.table()[])
  }
  return(data.table::rbindlist(lapply(items, as_dt_row), fill = TRUE)[])
}

#' Coerce columns of a data.table in place
#'
#' Applies `fn` to each named column by reference (via [data.table::set]); columns
#' not present are skipped. Typically used to turn epoch columns into POSIXct or
#' string columns into numeric after a generic parse.
#'
#' @param dt (class<data.table>) the table to mutate (by reference).
#' @param cols (character) column names to coerce (missing ones are ignored).
#' @param fn (function) applied to each column vector.
#' @return (class<data.table>) `dt`, invisibly, after coercion.
#' @importFrom data.table set
#' @export
coerce_cols <- function(dt, cols, fn) {
  assert_args_coerce_cols(dt, cols, fn)
  for (col in intersect(cols, names(dt))) {
    data.table::set(dt, j = col, value = fn(dt[[col]]))
  }
  return(invisible(dt))
}

#' Collapse plain-string array fields to semicolon-joined scalars
#'
#' Replaces each named field holding an array of short strings with one
#' `;`-joined character scalar, so a record stays one row with no list columns.
#' `;` is used (not `,`) because the values are short codes/identifiers; recover
#' the vector with `strsplit(value, ";", fixed = TRUE)`. Empty/missing arrays
#' become `NA_character_`. A once-per-session warning fires if a value already
#' contains a `;` (which a later split would corrupt).
#'
#' @param x (list) a named list (one record).
#' @param fields (character) names of the fields to collapse.
#' @return (list) the same record with those fields collapsed in place.
#' @export
collapse_string_array_fields <- function(x, fields) {
  for (nm in fields) {
    val <- x[[nm]]
    if (is.null(val) || length(val) == 0L) {
      x[[nm]] <- NA_character_
      next
    }
    if (is.list(val)) {
      val <- unlist(val, use.names = FALSE)
    }
    if (is.atomic(val) && length(val) >= 1L) {
      val_chr <- as.character(val)
      val_chr <- val_chr[!is.na(val_chr)]
      if (any(grepl(";", val_chr, fixed = TRUE))) {
        rlang::warn(
          sprintf("collapse_string_array_fields: a value in '%s' contains ';'; a later split would corrupt it.", nm),
          .frequency = "once",
          .frequency_id = "connectcore_collapse_semicolon"
        )
      }
      x[[nm]] <- if (length(val_chr) == 0L) NA_character_ else paste(val_chr, collapse = ";")
    }
  }
  return(x)
}
