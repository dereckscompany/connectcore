# Endpoint loading from environment variables.

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
