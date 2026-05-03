// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import json-pointer show *

import .action show Ref
import .build-context
import .gen
import .resource-loader
import .schema
import .store_
import .validation
import .vocabulary
import .uri

export Result Detail BuildContext OPENAPI-3-1-URI JSON-SCHEMA-2020-12-URI

/**
An implementation of the JSON Schema Specification Draft 2022-12.
https://json-schema.org/draft/2020-12/json-schema-core#name-the-vocabulary-keyword

Start by building a $JsonSchema with $build. The returned schema can then be
  used to validate JSON values with $JsonSchema.validate.

# Example

```
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

  result = schema.validate {
    "name": "John Doe",
    "age": -5  // Not valid, as age is less than minimum.
  }
  print result.is-valid  // => false.
```

Note that the $Result object contains more information than just whether
  the validation succeeded.
*/

/**
Builds the $JsonSchema for the given JSON value $o.

Conceptually this consists of:
  - Parsing the JSON value into a schema.
  - Resolving all references.

Users may want to use the $parse and $resolve methods directly, if they want to
  control the process more closely. For example, the OpenAPI specification has
  schemas intermingled with other data, in which case $parse needs to be called
  multiple times with different json-pointers.
*/
build o/any --resource-loader/ResourceLoader=HttpResourceLoader -> JsonSchema:
  context := BuildContext --resource-loader=resource-loader
  schema := parse o --context=context
  resolve --context=context
  return schema

/**
Parses the given object $o as a JSON schema.

The result is not yet resolved. (See $resolve).
In many cases, the function $build should be used, as it resolves once the schema
  has been parsed.
*/
parse o/any -> JsonSchema
    --context/BuildContext
    --json-pointer/JsonPointer=JsonPointer
    --base-uri/UriReference?=null
:
  root-schema := Schema.parse_ o
      --context=context
      --json-pointer=json-pointer
      --parent=null
      --base-uri=base-uri
  return JsonSchema.private_ root-schema context.store

/**
Resolves all references that were collected during the parsing of the schema.

The given $context contains the references and the store with all the schemas.
*/
resolve --context/BuildContext:
  store := context.store
  resource-loader := context.resource-loader
  // Resolve all references.
  while not context.refs.is-empty:
    pending := context.refs
    context.refs = []
    pending.do: | ref/Ref |
      target-uri := ref.target-uri
      target-uri-no-fragment := target-uri.with-fragment null
      context.resource-uri-id-mapping.get target-uri-no-fragment --if-present=: | replacement/UriReference |
        // The target URI is actually an ID that was defined in a resource.
        target-uri = replacement.with-fragment target-uri.fragment
      target := target-uri.to-string
      resolved := store.get target

      if not resolved:
        missing-resource-url := target-uri.with-fragment null
        missing-resource-url-string := missing-resource-url.to-string
        if not store.get missing-resource-url-string:
          resource-json := resource-loader.load missing-resource-url-string
          // Building the schema will automatically add its json-pointer to the store.
          schema := Schema.parse_ resource-json
              --context=context
              --json-pointer=JsonPointer
              --parent=null
              --base-uri=missing-resource-url
          // The downloaded resource might have an ID that is different than the URL.
          store.add missing-resource-url-string schema
          // Try again to find the target.
          resolved = store.get target
        if not resolved:
          throw "Could not resolve reference: $target"

      dynamic-fragment := store.get-dynamic-fragment target
      ref.set-target resolved --dynamic-fragment=dynamic-fragment

  if not context.discriminators.is-empty:
    VocabularyOpenApi.resolve-discriminators --context=context

/**
A parsed JSON Schema.

Contrary to a pure $Schema, this class also has information (the $Store) to
  resolve dynamic references.
*/
class JsonSchema:
  schema/Schema
  store_/Store

  constructor.private_ .schema .store_:

  /**
  Validates the given object $o, against this schema.
  */
  validate o/any --collect-annotations/bool=true --collect-all-errors/bool=false -> Result:
    location := InstantiatedSchema null "" schema
    context := ValidationContext
        --store=store_
        --needs-all-errors=collect-all-errors
        --needs-annotations=collect-annotations
    subresult := location.validate o --context=context --instance-pointer=JsonPointer
    return Result.private_ subresult
