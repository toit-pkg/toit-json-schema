// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import json-schema

main:
  schema := json-schema.build {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "name": {
        "type": "string"
      },
      "age": {
        "type": "integer",
        "minimum": 0
      }
    },
    "required": ["name", "age"]
  }

  result := schema.validate {
    "name": "John Doe",
    "age": 30
  }
  print result.is-valid  // => true.
  expect result.is-valid

  result = schema.validate {
    "name": "John Doe",
    "age": -5  // Not valid, as age is less than minimum.
  }
  print result.is-valid  // => false.
  expect-not result.is-valid
