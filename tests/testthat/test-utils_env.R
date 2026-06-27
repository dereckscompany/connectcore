# Credential / endpoint loading from environment variables.

test_that("env_or returns the variable when set, else the default", {
  withr::local_envvar(CONNECTCORE_TEST_VAR = "live")
  expect_identical(env_or("CONNECTCORE_TEST_VAR"), "live")
  expect_identical(env_or("CONNECTCORE_DOES_NOT_EXIST", "fallback"), "fallback")
})

test_that("env_or treats an empty variable as unset", {
  withr::local_envvar(CONNECTCORE_TEST_VAR = "")
  expect_identical(env_or("CONNECTCORE_TEST_VAR", "fallback"), "fallback")
})

test_that("url_getter resolves the env var by default and accepts an override", {
  getter <- url_getter("CONNECTCORE_BASE_URL", "https://default.test")
  expect_type(getter, "closure")
  expect_identical(getter(), "https://default.test")
  expect_identical(getter("https://override.test"), "https://override.test")

  withr::local_envvar(CONNECTCORE_BASE_URL = "https://from-env.test")
  expect_identical(getter(), "https://from-env.test")
})

test_that("load_keys resolves a credential spec into a named list", {
  withr::local_envvar(CC_KEY = "pub", CC_SECRET = "priv")
  keys <- load_keys(list(api_key = "CC_KEY", api_secret = "CC_SECRET"))
  expect_identical(keys, list(api_key = "pub", api_secret = "priv"))
})

test_that("load_keys warns on a missing field but still returns the list", {
  withr::local_envvar(CC_KEY = "pub", CC_SECRET = "")
  expect_warning(
    keys <- load_keys(list(api_key = "CC_KEY", api_secret = "CC_SECRET")),
    "api_secret"
  )
  expect_identical(keys$api_key, "pub")
})

test_that("load_keys can be silenced", {
  withr::local_envvar(CC_SECRET = "")
  expect_silent(load_keys(list(api_secret = "CC_SECRET"), warn = FALSE))
})
