// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import json-schema
import json-schema.gen as schema-gen

/// Builds a schema from a JSON map and generates code in memory.
/// Returns a Map from path to generated code string.
gen-code schema-json/Map --out-path/string="test.toit" -> Map:
  schema := json-schema.build schema-json
  generator := schema-gen.Gen out-path
  return generator.gen [schema] --in-memory

main:
  test-simple-object
  test-nested-object
  test-circular-ref
  test-additional-properties-object
  test-array-of-objects
  test-description-toitdoc
  test-to-json
  test-mixin-for-allof
  test-oneof-discriminator
  test-oneof-no-discriminator
  test-anyof
  test-oneof-with-allof-variants

test-simple-object:
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
      },
      "age": {
        "type": "integer",
      },
    },
    "required": ["name"],
  }
  code := result["test.toit"]
  // The generated code should contain a class with name and age fields.
  expect (code.contains "name")
  expect (code.contains "age")
  expect (code.contains "name/string")
  expect (code.contains "age/int")
  // All fields use type-appropriate defaults (for mixin compatibility).
  expect (code.contains "name/string := \"\"")
  expect (code.contains "age/int := 0")
  // Constructor is named from-json.
  expect (code.contains "constructor.from-json")

test-nested-object:
  // Tests that nested object properties reference the correct class
  // (the child class, not the parent).
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "address": {
        "type": "object",
        "properties": {
          "street": {
            "type": "string",
          },
        },
      },
    },
  }
  code := result["test.toit"]
  // Should generate both Root and RootAddress classes.
  expect (code.contains "class Root")
  expect (code.contains "class RootAddress")
      --message="Expected a class for the nested address object"
  // The Root constructor should call RootAddress.from-json for the nested object.
  expect (code.contains "RootAddress.from-json")
      --message="Expected nested object to use its own class for from-json"

test-circular-ref:
  // Tests that circular $ref doesn't cause infinite recursion.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
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
  }
  code := result["test.toit"]
  // Should complete without hanging and produce a class.
  expect (code.contains "class Node")

test-additional-properties-object:
  // Tests that schemas referenced via additionalProperties are collected.
  // The outer object has named properties too, so it isn't treated as a pure map.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "name": { "type": "string" },
    },
    "additionalProperties": {
      "type": "object",
      "properties": {
        "value": { "type": "integer" },
      },
    },
  }
  code := result["test.toit"]
  // Should generate a class for the additionalProperties type.
  expect (code.contains "class RootValue")
      --message="Expected a class for the additionalProperties schema"

test-array-of-objects:
  // Tests that arrays of objects get element conversion in the constructor.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "name": { "type": "string" },
          },
        },
      },
    },
  }
  code := result["test.toit"]
  // Should generate an element class.
  expect (code.contains "class RootItemsElement")
      --message="Expected a class for the array element type"
  // The constructor should map elements through from-json.
  expect (code.contains ".map:")
      --message="Expected array elements to be mapped through from-json"

test-description-toitdoc:
  // Tests that JSON Schema descriptions become toitdoc comments.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "description": "A person object.",
    "properties": {
      "name": {
        "type": "string",
        "description": "The person's name.",
      },
    },
  }
  code := result["test.toit"]
  // Class should have a toitdoc comment.
  expect (code.contains "A person object.")
      --message="Expected class toitdoc from description"
  // Field should have a toitdoc comment.
  expect (code.contains "The person's name.")
      --message="Expected field toitdoc from description"

test-to-json:
  // Tests that a to-json method is generated.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "name": { "type": "string" },
      "address": {
        "type": "object",
        "properties": {
          "street": { "type": "string" },
        },
      },
    },
  }
  code := result["test.toit"]
  // Should have a to-json method.
  expect (code.contains "to-json")
      --message="Expected a to-json method"
  // The to-json method should return a Map.
  expect (code.contains "to-json -> Map")
      --message="Expected to-json to return Map"
  // Nested objects should have .to-json called on them.
  expect (code.contains ".to-json")
      --message="Expected nested object to call .to-json"

test-mixin-for-allof:
  // Tests that schemas used in allOf get a mixin generated.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "Pet": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
        },
      },
      "Dog": {
        "allOf": [
          { "\$ref": "#/\$defs/Pet" },
          {
            "type": "object",
            "properties": {
              "bark": { "type": "string" },
            },
          },
        ],
      },
    },
    "\$ref": "#/\$defs/Dog",
  }
  code := result["test.toit"]
  // Pet is used in an allOf, so it should get a mixin.
  expect (code.contains "mixin PetMixin")
      --message="Expected mixin for Pet (used in allOf)"
  // Pet class should extend Object with PetMixin.
  expect (code.contains "class Pet extends Object with PetMixin")
      --message="Expected Pet to extend Object with PetMixin"
  // Dog should extend Pet (allOf with $ref).
  expect (code.contains "class Dog extends Pet")
      --message="Expected Dog to extend Pet"
  // Dog's constructor should call super.from-json.
  expect (code.contains "super.from-json")
      --message="Expected Dog constructor to call super.from-json"
  // Dog should have its own bark field.
  expect (code.contains "bark/string")
      --message="Expected Dog to have bark field"

test-oneof-discriminator:
  // Tests oneOf with discriminator → abstract base + factory + subclasses.
  // Uses OpenAPI 3.1 dialect since discriminator is an OpenAPI extension.
  result := gen-code {
    "\$schema": "https://spec.openapis.org/oas/3.1/dialect/base",
    "\$defs": {
      "Dog": {
        "type": "object",
        "properties": {
          "bark": { "type": "string" },
        },
      },
      "Cat": {
        "type": "object",
        "properties": {
          "purr": { "type": "boolean" },
        },
      },
    },
    "discriminator": {
      "propertyName": "petType",
      "mapping": {
        "dog": "#/\$defs/Dog",
        "cat": "#/\$defs/Cat",
      },
    },
    "oneOf": [
      { "\$ref": "#/\$defs/Dog" },
      { "\$ref": "#/\$defs/Cat" },
    ],
  }
  code := result["test.toit"]
  // Should generate abstract base class.
  expect (code.contains "abstract class Root")
      --message="Expected abstract oneOf base class"
  // Should have a factory constructor.from-json.
  expect (code.contains "constructor.from-json")
      --message="Expected factory from-json on base class"
  // Should have discriminator dispatch.
  expect (code.contains "petType")
      --message="Expected discriminator property in factory"
  // Subclasses should extend the base.
  expect (code.contains "class Dog extends Root")
      --message="Expected Dog to extend the oneOf base class"
  expect (code.contains "class Cat extends Root")
      --message="Expected Cat to extend the oneOf base class"
  // Subclasses should call super.from-sub_.
  expect (code.contains "super.from-sub_")
      --message="Expected variant to call super.from-sub_"

test-oneof-no-discriminator:
  // Tests oneOf without discriminator → heuristic field-based dispatch.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "Circle": {
        "type": "object",
        "properties": {
          "radius": { "type": "number" },
        },
        "required": ["radius"],
      },
      "Rectangle": {
        "type": "object",
        "properties": {
          "width": { "type": "number" },
          "height": { "type": "number" },
        },
        "required": ["width", "height"],
      },
    },
    "oneOf": [
      { "\$ref": "#/\$defs/Circle" },
      { "\$ref": "#/\$defs/Rectangle" },
    ],
  }
  code := result["test.toit"]
  // Should generate abstract base class.
  expect (code.contains "abstract class Root")
      --message="Expected abstract oneOf base class"
  // Should use .contains for heuristic dispatch.
  expect (code.contains ".contains")
      --message="Expected field-based heuristic dispatch"
  // Subclasses should extend the base.
  expect (code.contains "class Circle extends Root")
      --message="Expected Circle to extend Root"
  expect (code.contains "class Rectangle extends Root")
      --message="Expected Rectangle to extend Root"

test-anyof:
  // Tests that anyOf is treated identically to oneOf.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "A": {
        "type": "object",
        "properties": { "a-field": { "type": "string" } },
        "required": ["a-field"],
      },
      "B": {
        "type": "object",
        "properties": { "b-field": { "type": "string" } },
        "required": ["b-field"],
      },
    },
    "anyOf": [
      { "\$ref": "#/\$defs/A" },
      { "\$ref": "#/\$defs/B" },
    ],
  }
  code := result["test.toit"]
  // Should generate abstract base class, same as oneOf.
  expect (code.contains "abstract class Root")
      --message="Expected abstract anyOf base class"
  expect (code.contains "class A extends Root")
      --message="Expected A to extend Root"
  expect (code.contains "class B extends Root")
      --message="Expected B to extend Root"

test-oneof-with-allof-variants:
  // Tests oneOf where variants use allOf (common OpenAPI pattern).
  // Dog/Cat use allOf to extend Pet, and a discriminated oneOf selects between them.
  result := gen-code {
    "\$schema": "https://spec.openapis.org/oas/3.1/dialect/base",
    "\$defs": {
      "Pet": {
        "type": "object",
        "properties": { "name": { "type": "string" } },
      },
      "Dog": {
        "allOf": [
          { "\$ref": "#/\$defs/Pet" },
          { "type": "object", "properties": { "bark": { "type": "string" } } },
        ],
      },
      "Cat": {
        "allOf": [
          { "\$ref": "#/\$defs/Pet" },
          { "type": "object", "properties": { "purr": { "type": "boolean" } } },
        ],
      },
    },
    "discriminator": {
      "propertyName": "petType",
      "mapping": { "dog": "#/\$defs/Dog", "cat": "#/\$defs/Cat" },
    },
    "oneOf": [
      { "\$ref": "#/\$defs/Dog" },
      { "\$ref": "#/\$defs/Cat" },
    ],
  }
  code := result["test.toit"]
  // Should generate abstract oneOf base with factory.
  expect (code.contains "abstract class Root")
      --message="Expected abstract oneOf base class"
  expect (code.contains "constructor.from-json data")
      --message="Expected factory on base class"
  // Dog and Cat extend Pet (allOf takes precedence for superclass).
  expect (code.contains "class Dog extends Pet")
      --message="Expected Dog to extend Pet via allOf"
  // Pet should have a mixin (used in allOf).
  expect (code.contains "mixin PetMixin")
      --message="Expected PetMixin for Pet"
  // Dog should have its own fields.
  expect (code.contains "bark/string")
      --message="Expected Dog to have bark field"
