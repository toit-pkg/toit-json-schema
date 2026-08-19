// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

/**
Smoke test: generated code must successfully pass `toit analyze`.

Catches regressions where the generator emits syntactically valid but
  type-incorrect code (or vice versa).
*/

import expect show *
import host
import host.directory
import host.file
import host.pipe
import json-schema
import json-schema.gen as schema-gen

main args/List:
  toit := args[0]
  host.with-tmp-directory "/tmp/gen-compile-test-": | tmp-dir |
    test-each toit tmp-dir

test-each toit/string tmp-dir/string -> none:
  cases := [
    ["simple-object", {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "age": { "type": "integer" },
      },
      "required": ["name"],
    }],
    ["nested-object", {
      "type": "object",
      "properties": {
        "address": {
          "type": "object",
          "properties": { "street": { "type": "string" } },
        },
      },
    }],
    ["allof-mixin", {
      "\$defs": {
        "Pet": { "type": "object", "properties": { "name": { "type": "string" } } },
        "Dog": {
          "allOf": [
            { "\$ref": "#/\$defs/Pet" },
            { "type": "object", "properties": { "bark": { "type": "string" } } },
          ],
        },
      },
      "\$ref": "#/\$defs/Dog",
    }],
    ["oneof-discriminator", {
      "\$schema": "https://spec.openapis.org/oas/3.1/dialect/base",
      "\$defs": {
        "Cat": { "type": "object", "properties": { "purr": { "type": "boolean" } } },
        "Dog": { "type": "object", "properties": { "bark": { "type": "string" } } },
      },
      "discriminator": {
        "propertyName": "kind",
        "mapping": { "cat": "#/\$defs/Cat", "dog": "#/\$defs/Dog" },
      },
      "oneOf": [
        { "\$ref": "#/\$defs/Cat" },
        { "\$ref": "#/\$defs/Dog" },
      ],
    }],
    ["typed-map", {
      "type": "object",
      "additionalProperties": { "type": "integer" },
    }],
    ["array-of-objects", {
      "type": "array",
      "items": {
        "type": "object",
        "properties": { "id": { "type": "integer" } },
      },
    }],
    ["circular-ref", {
      "\$defs": {
        "node": {
          "type": "object",
          "properties": {
            "value": { "type": "string" },
            "children": {
              "type": "array",
              "items": { "\$ref": "#/\$defs/node" },
            },
          },
        },
      },
      "\$ref": "#/\$defs/node",
    }],
    ["multi-type-unions", {
      "type": "object",
      "properties": {
        "name": { "type": ["string", "null"] },
        "amount": { "type": ["integer", "number"] },
      },
    }],
    ["nullable-ref-and-array", {
      "\$defs": {
        "Tag": {
          "type": "object",
          "properties": { "name": { "type": "string" } },
        },
      },
      "type": "object",
      "properties": {
        "tag": { "\$ref": "#/\$defs/Tag" },
        "tags": {
          "type": "array",
          "items": { "\$ref": "#/\$defs/Tag" },
        },
      },
    }],
    ["core-name-shadowing", {
      "\$defs": {
        "Map": {
          "type": "object",
          "properties": { "value": { "type": "string" } },
        },
        "List": {
          "type": "object",
          "properties": {
            "values": {
              "type": "array",
              "items": { "\$ref": "#/\$defs/Map" },
            },
          },
        },
      },
      "type": "object",
      "properties": {
        "map": { "\$ref": "#/\$defs/Map" },
        "list": { "\$ref": "#/\$defs/List" },
        "lookup": {
          "type": "object",
          "additionalProperties": { "type": "integer" },
        },
      },
    }],
  ]

  cases.do: | pair/List |
    name/string := pair[0]
    schema-json/Map := pair[1]
    schema := json-schema.build schema-json
    files := schema-gen.gen [schema] --module="schema.toit"
    case-dir := "$tmp-dir/$name"
    directory.mkdir --recursive case-dir
    files.do: | filename/string code/string |
      file.write-contents --path="$case-dir/$filename" code
    code := files["schema.toit"]
    exit-code := pipe.run-program toit "analyze" "$case-dir/schema.toit"
    if exit-code != 0:
      print "Failed case: $name"
      print "Generated code:"
      print code
    expect (exit-code == 0)
        --message="`toit analyze` failed for case: $name (exit $exit-code)"
