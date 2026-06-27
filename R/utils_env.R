# File: R/utils_env.R
# Credential / endpoint loading from environment variables. Every connector reads
# its keys and base URL from env vars with a fallback; only the var names and
# defaults differ, so connectors build thin wrappers over these factories.

#' Read an environment variable with a default
#'
#' @param var (scalar<character>) the environment variable name.
#' @param default (scalar<character>) returned when the variable is unset/empty.
#'   Default `""`.
#' @return (scalar<character>) the variable's value, or `default`.
#' @export
env_or <- function(var, default = "") {
  assert_args_env_or(var, default)
  value <- Sys.getenv(var, unset = default)
  if (!nzchar(value)) {
    return(default)
  }
  return(value)
}

#' Make a base-URL getter backed by an environment variable
#'
#' Returns a function `function(url = <env or default>)` — the standard connector
#' pattern. Calling it with no argument resolves the env var (falling back to the
#' default); passing `url` overrides.
#'
#' @param var (scalar<character>) the environment variable name.
#' @param default (scalar<character>) the fallback URL.
#' @return (function) a getter `function(url)`.
#' @export
url_getter <- function(var, default) {
  assert_args_url_getter(var, default)
  getter <- function(url = env_or(var, default)) {
    return(url)
  }
  return(assert_return_url_getter(getter))
}

#' Load API credentials from environment variables
#'
#' Reads a named set of credential fields from env vars into a list (the shape a
#' signer expects, e.g. `list(api_key = ..., api_secret = ...)`). Warns (rather
#' than aborts) if any field is empty, since public endpoints work without keys.
#'
#' @param spec (list) a named list mapping each credential field to its env var
#'   name, e.g. `list(api_key = "BINANCE_API_KEY", api_secret = "BINANCE_API_SECRET")`.
#' @param warn (scalar<logical>) warn when a field resolves empty. Default `TRUE`.
#' @return (list) a named list of the resolved credential values.
#' @export
load_keys <- function(spec, warn = TRUE) {
  assert_args_load_keys(spec, warn)
  keys <- lapply(spec, function(var) Sys.getenv(var, unset = ""))
  empty <- names(keys)[!nzchar(unlist(keys))]
  if (warn && length(empty) > 0L) {
    rlang::warn(sprintf(
      "Missing credential(s): %s. Public endpoints will still work.",
      paste(empty, collapse = ", ")
    ))
  }
  return(keys)
}
