// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import json-schema.regex_ as regex

main:
  r := regex.parse "a|b"
  expect (r.match "a")
  expect (r.match "b")
  expect-not (r.match "c")

  r = regex.parse "^a|b\$"
  expect (r.match "a")
  expect (r.match "b")
  expect-not (r.match "c")

  r = regex.parse "a*"
  expect (r.match "")
  expect (r.match "a")
  expect (r.match "aa")
  expect (r.match "b") // Regex is not anchored.

  r = regex.parse "^a*\$"
  expect (r.match "")
  expect (r.match "a")
  expect (r.match "aa")
  expect-not (r.match "b")

  r = regex.parse "a+"
  expect-not (r.match "")
  expect (r.match "a")
  expect (r.match "aa")
  expect-not (r.match "b")

  r = regex.parse "^a+\$"
  expect-not (r.match "")
  expect (r.match "a")
  expect (r.match "aa")
  expect-not (r.match "b")

  r = regex.parse "a?"
  expect (r.match "")
  expect (r.match "a")
  expect (r.match "aa") // Regex is not anchored.
  expect (r.match "b") // Regex is not anchored.

  r = regex.parse "^a?\$"
  expect (r.match "")
  expect (r.match "a")
  expect-not (r.match "aa")
  expect-not (r.match "b")

  r = regex.parse "a{2}"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")  // Regex is not anchored.

  r = regex.parse "^a{2}\$"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect-not (r.match "aaa")

  r = regex.parse "a{2,}"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")

  r = regex.parse "a{2,3}"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")
  expect (r.match "aaaa") // Regex is not anchored.

  r = regex.parse "^a{2,3}\$"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")
  expect-not (r.match "aaaa")

  r = regex.parse "a{2,3}?"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")
  expect (r.match "aaaa") // Regex is not anchored.

  r = regex.parse "^a{2,3}?\$"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")
  expect-not (r.match "aaaa")

  r = regex.parse "a{2,3}+"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")
  expect (r.match "aaaa")
  expect (r.match "aaaaa")

  r = regex.parse "^a{2,3}+\$"
  expect-not (r.match "")
  expect-not (r.match "a")
  expect (r.match "aa")
  expect (r.match "aaa")
  expect (r.match "aaaa")
  expect (r.match "aaaaa")

  r = regex.parse "(a|b)*"
  expect (r.match "")
  expect (r.match "a")
  expect (r.match "b")
  expect (r.match "ab")
  expect (r.match "ba")
  expect (r.match "abab")
  expect (r.match "c")  // Regex is not anchored.

  r = regex.parse "^(a|b)*\$"
  expect (r.match "")
  expect (r.match "a")
  expect (r.match "b")
  expect (r.match "ab")
  expect (r.match "ba")
  expect (r.match "abab")
  expect-not (r.match "c")

  r = regex.parse "^()*\$"
  expect (r.match "")
  expect-not (r.match "a")

  r = regex.parse "^()+\$"
  expect (r.match "")
  expect-not (r.match "a")

  r = regex.parse "^[0-9]*\$"
  expect (r.match "")
  expect (r.match "0")
  expect (r.match "12345")
