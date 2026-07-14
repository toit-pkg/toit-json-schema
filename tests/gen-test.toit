// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import json-schema
import json-schema.gen as schema-gen
import toit-gen

/// Builds a schema from a JSON map and generates code in memory.
/// Returns a Map from module filename to generated code string.
gen-code schema-json/Map --module/string="test.toit" -> Map:
  schema := json-schema.build schema-json
  return schema-gen.gen [schema] --module=module

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
  test-nullable-type-union
  test-numeric-type-union
  test-incompatible-type-union
  test-kebab-case-property
  test-deeply-nested
  test-populate-multi-library
  test-models-lookup
  test-populate-class-seed
  test-allof-multiple-refs-with-overlap
  test-oneof-undecidable-no-distinguishing-field
  test-oneof-required-subset-ordered
  test-nullable-ref-and-array-null-safe
  test-oneof-catch-all-variant

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
  // Required fields use late-init; optional fields are nullable.
  expect (code.contains "name/string := ?")
  expect (code.contains "age/int? := null")
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
  // Tests allOf with $ref: parent becomes an interface, child class
  // implements it. The inline subschema contributes its own fields.
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
  // No mixins are generated.
  expect (not code.contains "mixin ")
      --message="Did not expect any mixin in generated code"
  // Pet is referenced as an allOf parent → public face is an interface,
  // private impl class holds the actual fields/methods.
  expect (code.contains "interface Pet")
      --message="Expected interface Pet (used as allOf parent)"
  expect (code.contains "class PetImpl_ implements Pet")
      --message="Expected private impl class PetImpl_ implementing Pet"
  // Pet's interface exposes a factory that delegates to the impl.
  expect (code.contains "return PetImpl_.from-json")
      --message="Expected Pet.from-json factory delegating to PetImpl_"
  // Dog is a leaf class — implements Pet directly with all fields.
  expect (code.contains "class Dog implements Pet")
      --message="Expected Dog to implement Pet via allOf"
  expect (code.contains "name/string")
      --message="Expected Dog to declare name (transitive from Pet)"
  expect (code.contains "bark/string")
      --message="Expected Dog to have bark field (from inline allOf)"

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
  // Dog and Cat extend Root (oneOf variant) and implements Pet (allOf parent).
  expect (code.contains "class Dog extends Root implements Pet")
      --message="Expected Dog to extend Root and implement Pet"
  // No mixins generated.
  expect (not code.contains "mixin ")
      --message="Did not expect any mixin in generated code"
  // Pet is referenced as an allOf parent → interface + private impl.
  expect (code.contains "interface Pet")
      --message="Expected Pet as interface (used as allOf parent)"
  expect (code.contains "class PetImpl_")
      --message="Expected private PetImpl_ class"
  // Dog should have its own fields.
  expect (code.contains "bark/string")
      --message="Expected Dog to have bark field"

test-nullable-type-union:
  // ["string","null"] should resolve to string (not any).
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "name": { "type": ["string", "null"] },
    },
  }
  code := result["test.toit"]
  expect (code.contains "name/string")
      --message="Expected nullable string union to resolve to string"
  expect (not code.contains "name/any")
      --message="Nullable union should not degrade to any"

test-numeric-type-union:
  // ["integer","number"] should resolve to num (not any).
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "amount": { "type": ["integer", "number"] },
      "amount-or-null": { "type": ["integer", "number", "null"] },
    },
  }
  code := result["test.toit"]
  expect (code.contains "amount/num")
      --message="Expected numeric union to resolve to num"
  expect (code.contains "amount-or-null/num")
      --message="Expected numeric+null union to resolve to num"

test-incompatible-type-union:
  // ["string","integer"] has no good Toit type — falls through to any.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "value": { "type": ["string", "integer"] },
    },
  }
  code := result["test.toit"]
  expect (code.contains "value/any")
      --message="Expected mixed-type union to fall through to any"

test-kebab-case-property:
  // Property names with kebab/snake/camel case map to kebab-cased Toit fields
  // (Toit naming convention), but to-json preserves the original JSON keys.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "user-name": { "type": "string" },
      "lastModified": { "type": "string" },
      "is_admin": { "type": "boolean" },
    },
  }
  code := result["test.toit"]
  expect (code.contains "user-name/string")
      --message="Expected kebab-cased Toit field"
  expect (code.contains "last-modified/string")
      --message="Expected camelCase property normalized to kebab-case"
  expect (code.contains "is-admin/bool")
      --message="Expected snake_case property normalized to kebab-case"
  // from-json reads using the original JSON key (not the Toit field name).
  // Nullable fields use data.get so a missing key resolves to null.
  expect (code.contains "data.get \"lastModified\"")
      --message="Expected from-json to read with original camel key via data.get"
  expect (code.contains "data.get \"is_admin\"")
      --message="Expected from-json to read with original snake key via data.get"
  // to-json emits the original JSON key, preserving round-trip fidelity.
  expect (code.contains "\"user-name\"")
      --message="Expected to-json to emit original kebab key"
  expect (code.contains "\"lastModified\"")
      --message="Expected to-json to emit original camel key"
  expect (code.contains "\"is_admin\"")
      --message="Expected to-json to emit original snake key"

test-deeply-nested:
  // Three-level nested objects: each layer should get its own class
  // named by the path from the root.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "config": {
        "type": "object",
        "properties": {
          "database": {
            "type": "object",
            "properties": {
              "host": { "type": "string" },
            },
          },
        },
      },
    },
  }
  code := result["test.toit"]
  expect (code.contains "class Root")
      --message="Expected Root class"
  expect (code.contains "class RootConfig")
      --message="Expected RootConfig class for second level"
  expect (code.contains "class RootConfigDatabase")
      --message="Expected RootConfigDatabase class for third level"
  // Each level's from-json should reference the next level's class.
  expect (code.contains "RootConfig.from-json")
      --message="Expected Root.from-json to delegate to RootConfig"
  expect (code.contains "RootConfigDatabase.from-json")
      --message="Expected RootConfig.from-json to delegate to RootConfigDatabase"

test-populate-multi-library:
  // Routes generated classes into a dedicated `models.toit` library that
  // sits next to a hand-built `api.toit`. Verifies populate adds the model
  // class to the right library and that program.gen renders both files.
  schema := json-schema.build {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": { "name": { "type": "string" } },
  }
  program := toit-gen.Program
  api-lib := toit-gen.Library "api.toit"
  models-lib := toit-gen.Library "models.toit"
  program.libraries.add api-lib
  program.libraries.add models-lib
  schema-gen.populate program [schema] --library-for-uri=:: models-lib
  files := program.gen --in-memory
  expect (files.contains "models.toit")
      --message="Expected models.toit in output"
  expect (files.contains "api.toit")
      --message="Expected api.toit in output"
  expect ((files["models.toit"]).contains "class Root")
      --message="Expected Root class to land in models.toit"
  expect (not (files["api.toit"]).contains "class Root")
      --message="Root must not appear in api.toit"

test-models-lookup:
  // Verifies Models.lookup-by-uri and Models.lookup return the toit-gen.Class
  // for a generated schema. Primitive schemas should return null.
  json-schema-doc := json-schema.build {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": { "name": { "type": "string" } },
  }
  program := toit-gen.Program
  lib := toit-gen.Library "schema.toit"
  program.libraries.add lib
  models := schema-gen.populate program [json-schema-doc] --library-for-uri=:: lib

  // Lookup by Schema.
  clazz := models.lookup json-schema-doc.schema
  expect (clazz != null) --message="Expected lookup to return a Class for the root object schema"
  expect-equals "Root" clazz.preferred-name

  // Lookup by URI.
  clazz-by-uri := models.lookup-by-uri json-schema-doc.schema.absolute-location
  expect (clazz-by-uri == clazz)
      --message="lookup and lookup-by-uri should return the same Class"

test-populate-class-seed:
  // Verifies that --class-seed lets a caller pre-name a schema by URI,
  // overriding the auto-derived name. This is what openapi-gen needs for
  // inline schemas where the JSON-pointer-derived name ("schema") is
  // useless.
  json-schema-doc := json-schema.build {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": { "name": { "type": "string" } },
  }
  program := toit-gen.Program
  lib := toit-gen.Library "schema.toit"
  program.libraries.add lib
  uri := json-schema-doc.schema.absolute-location
  models := schema-gen.populate program [json-schema-doc]
      --library-for-uri=:: lib
      --class-seed={uri: "Pet"}
  clazz := models.lookup-by-uri uri
  expect (clazz != null) --message="Expected lookup to return a Class for the seeded schema"
  expect-equals "Pet" clazz.preferred-name

test-allof-multiple-refs-with-overlap:
  // allOf with two $ref parents. Both parents become interfaces; C is a
  // leaf class that implements both. C declares all transitive fields
  // directly (deduped by name — `shared` appears once on C).
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "A": {
        "type": "object",
        "properties": {
          "shared": { "type": "string" },
          "a-only": { "type": "integer" },
        },
      },
      "B": {
        "type": "object",
        "properties": {
          "shared": { "type": "string" },
          "b-only": { "type": "boolean" },
        },
      },
      "C": {
        "allOf": [
          { "\$ref": "#/\$defs/A" },
          { "\$ref": "#/\$defs/B" },
        ],
      },
    },
    "\$ref": "#/\$defs/C",
  }
  code := result["test.toit"]
  // A and B are allOf parents → interfaces.
  expect (code.contains "interface A")
      --message="Expected A as interface"
  expect (code.contains "interface B")
      --message="Expected B as interface"
  // C is a leaf (not used as parent) → regular class implementing both.
  expect (code.contains "class C implements A B")
      --message="Expected C to implement A and B"
  // No mixins.
  expect (not code.contains "mixin ")
      --message="Did not expect any mixin"
  // C declares all transitive fields directly: shared, a-only, b-only.
  expect (code.contains "b-only/bool")
      --message="Expected b-only field on C"
  expect (code.contains "a-only/int")
      --message="Expected a-only field on C"
  // `shared` appears exactly once on C (deduped across A and B).
  c-body-start := code.index-of "class C implements"
  c-body := code[c-body-start..]
  shared-decls := 0
  c-body.split "\n": | line/string |
    if (line.trim.starts-with "shared/string"): shared-decls++
  expect-equals 1 shared-decls

test-oneof-undecidable-no-distinguishing-field:
  // A discriminator-less oneOf where one variant's properties are a strict
  // superset of another's. Codegen must fail rather than produce ambiguous
  // dispatch.
  schema-json := {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "Small": {
        "type": "object",
        "properties": { "x": { "type": "string" } },
      },
      "Big": {
        "type": "object",
        "properties": {
          "x": { "type": "string" },
          "y": { "type": "string" },
        },
      },
    },
    "oneOf": [
      { "\$ref": "#/\$defs/Small" },
      { "\$ref": "#/\$defs/Big" },
    ],
  }
  err := catch: gen-code schema-json
  expect (err is string) --message="Expected gen-code to throw"
  expect ((err as string).contains "cannot statically distinguish")
      --message="Expected error to mention undistinguishable variant; was: $err"

test-oneof-required-subset-ordered:
  // Variant A's required ⊂ variant B's required: dispatch checks B (the
  // superset) first — an input containing all of B's required properties can
  // only belong to B, so A's weaker check is safe afterwards.
  schema-json := {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "A": {
        "type": "object",
        "properties": {
          "shared": { "type": "string" },
          "a-extra": { "type": "string" },
        },
        "required": ["shared"],
      },
      "B": {
        "type": "object",
        "properties": {
          "shared": { "type": "string" },
          "more": { "type": "string" },
          "b-extra": { "type": "string" },
        },
        "required": ["shared", "more"],
      },
    },
    "oneOf": [
      { "\$ref": "#/\$defs/A" },
      { "\$ref": "#/\$defs/B" },
    ],
  }
  result := gen-code schema-json
  code := result["test.toit"]
  // B's check must test all of its required properties.
  expect (code.contains "(data.contains \"shared\") and (data.contains \"more\")")
      --message="Expected conjunction over B's required properties"
  b-dispatch := code.index-of "return B.from-json"
  a-dispatch := code.index-of "return A.from-json"
  expect b-dispatch >= 0 --message="Expected dispatch to B"
  expect a-dispatch >= 0 --message="Expected dispatch to A"
  expect b-dispatch < a-dispatch
      --message="Expected B (required superset) to be checked before A"

test-nullable-ref-and-array-null-safe:
  // Tests that nullable $ref and array-of-$ref fields generate null-safe
  // from-json/to-json: missing keys go through `data.get`, and the recursive
  // conversion is skipped when the value is null.
  result := gen-code {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "Tag": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
        },
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
  }
  code := result["test.toit"]
  // Nullable lookup uses data.get rather than data[...] to tolerate a
  // missing key.
  expect (code.contains "data.get \"tag\"")
      --message="Expected data.get for nullable \$ref field"
  expect (code.contains "data.get \"tags\"")
      --message="Expected data.get for nullable array field"
  // The recursive call is guarded so a null value short-circuits to null.
  expect (code.contains "== null) ? null : (Tag.from-json")
      --message="Expected null guard before recursive Tag.from-json call"
  expect (code.contains "== null) ? null : ((data.get \"tags\").map:")
      --message="Expected null guard before .map: walk over nullable array"
  // The to-json path is also null-safe.
  expect (code.contains "(tag == null) ? null : tag.to-json")
      --message="Expected to-json to skip .to-json on null \$ref field"
  expect (code.contains "(tags == null) ? null : (tags.map:")
      --message="Expected to-json to skip .map: walk on null array"

test-oneof-catch-all-variant:
  // A variant without required properties can't be distinguished by a
  // `contains` check. It is checked last, as an unconditional catch-all.
  schema-json := {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "\$defs": {
      "Tagged": {
        "type": "object",
        "properties": { "tag": { "type": "string" } },
        "required": ["tag"],
      },
      "Free": {
        "type": "object",
        "properties": { "note": { "type": "string" } },
      },
    },
    "oneOf": [
      { "\$ref": "#/\$defs/Free" },
      { "\$ref": "#/\$defs/Tagged" },
    ],
  }
  result := gen-code schema-json
  code := result["test.toit"]
  tagged-dispatch := code.index-of "return Tagged.from-json"
  free-dispatch := code.index-of "return Free.from-json"
  expect tagged-dispatch >= 0 --message="Expected dispatch to Tagged"
  expect free-dispatch >= 0 --message="Expected dispatch to Free"
  expect tagged-dispatch < free-dispatch
      --message="Expected the catch-all variant Free to be checked last"
  expect (not code.contains "No matching variant")
      --message="Expected no unreachable throw after the catch-all"
