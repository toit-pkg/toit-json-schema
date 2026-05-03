// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import json-pointer show *
import uuid show *

import .action
import .build-context
import .store_
import .uri
import .validation
import .vocabulary

class Schema:
  json-pointer/JsonPointer
  json-value/any
  schema-resource/SchemaResource_? := ?
  is-resolved/bool := false
  is-sorted_/bool := false
  absolute-location/UriReference

  /**
  If this schema is in an all-of chain where the super-parent has an
    OpenAPI discriminator, then this is the discriminator of that super parent.
  */
  all-of-discriminator/Discriminator? := null

  actions/List ::= []

  add-applicator applicator/Applicator:
    actions.add applicator

  add-assertion assertion/Assertion:
    actions.add assertion

  constructor.private_ .json-pointer .json-value --.schema-resource --.absolute-location:

  static parse_ o/any -> Schema
      --parent/Schema?
      --context/BuildContext
      --json-pointer/JsonPointer
      --base-uri/UriReference? = null
  :
    schema-resource/SchemaResource_ := ?
    if not parent or (o is Map and o.get "\$id"):
      schema-resource = SchemaResource_ o --parent=parent --base-uri=base-uri --build-context=context
      if parent:
        // Reset the json-pointer, unless this is the root schema, where the pointer
        // was passed in.
        json-pointer = JsonPointer
    else:
      schema-resource = parent.schema-resource

    escaped-json-pointer := json-pointer.to-fragment-string
    escaped-json-pointer = UriReference.normalize-fragment escaped-json-pointer
    schema-json-pointer-url := schema-resource.uri.with-fragment escaped-json-pointer

    result := Schema.private_ json-pointer o
        --schema-resource=schema-resource
        --absolute-location=schema-json-pointer-url

    if o is Map:
      result.schema-resource.vocabularies.do: | _ vocabulary/Vocabulary |
        vocabulary.add-actions --schema=result --context=context --json-pointer=json-pointer

      // All keywords that are not handled by the dialect are treated like annotations.
      o.do: | key/string value/any |
        if not result.schema-resource.handled-keywords.contains key:
          result.add-assertion (Annotation key value)

    context.store.add schema-json-pointer-url.to-string result
    if json-pointer.to-fragment-string == "":
      // Also add this schema without any fragment.
      context.store.add result.schema-resource.uri.to-string result
    return result

  instantiate --parent/InstantiatedSchema? --segment/string -> InstantiatedSchema:
    if json-value is bool:
      return InstantiatedSchemaBool parent segment this
    else:
      if not is-sorted_:
        actions.sort --in-place: | a/Action b/Action | a.order.compare-to b.order
        is-sorted_ = true
      return InstantiatedSchemaObject parent segment this

  uri-reference ref/string -> UriReference:
    reference := (UriReference.parse ref).normalize
    return reference.resolve --base=schema-resource.uri

  is-reference-only -> bool:
    if actions.size != 1: return false
    only-action := actions[0]
    return only-action is Ref

  reference-target -> Schema?:
    if not is-reference-only: return null
    ref-action := actions[0] as Ref
    return ref-action.target

  reference-target-uri -> UriReference?:
    if not is-reference-only: return null
    ref-action := actions[0] as Ref
    return ref-action.target-uri

  hash-code -> int:
    return absolute-location.hash-code

  operator == other/any -> bool:
    if other is not Schema: return false
    return absolute-location == (other as Schema).absolute-location

class ValidationContext:
  store/Store
  needs-annotations/bool
  needs-all-errors/bool

  constructor --.store --.needs-annotations/bool --.needs-all-errors/bool:

  with --needs-annotations/bool:
    return ValidationContext
        --store=store
        --needs-annotations=needs-annotations
        --needs-all-errors=needs-all-errors

/**
An instantiated schema is a schema that has been resolved and has a
  dynamic location in the schema tree.
*/
abstract class InstantiatedSchema:
  parent/InstantiatedSchema?
  segment/string
  schema/Schema?

  constructor parent/InstantiatedSchema? segment/string schema/Schema:
    return schema.instantiate --parent=parent --segment=segment

  constructor.from-sub_ .parent .segment .schema:

  operator [] segment/string -> InstantiatedSchema:
    return InstantiatedSchemaGroup this segment

  operator [] segment/string sub-schema/Schema -> InstantiatedSchema:
    return InstantiatedSchema this segment sub-schema

  do-schema-resources --reversed/True [block]:
    do-schema-resources_ --reversed null block

  do-schema-resources_ --reversed/True last-resource [block]:
    resources := []
    current := this
    while current != null:
      if current.schema:
        current-resource := current.schema.schema-resource
        if current-resource != last-resource:
          resources.add current-resource
          last-resource = current-resource
      current = current.parent

    resources.do --reversed block

  abstract validate o/any --context/ValidationContext --instance-pointer/JsonPointer -> SubResult

class InstantiatedSchemaGroup extends InstantiatedSchema:
  constructor parent/InstantiatedSchema? segment/string:
    super.from-sub_ parent segment null

  validate o/any --context/ValidationContext --instance-pointer/JsonPointer -> SubResult:
    unreachable

class InstantiatedSchemaObject extends InstantiatedSchema:
  constructor parent/InstantiatedSchema? segment/string schema/Schema:
    super.from-sub_ parent segment schema

  schema_ -> Schema:
    return schema as Schema

  validate o/any --context/ValidationContext --instance-pointer/JsonPointer -> SubResult:
    if schema_.all-of-discriminator:
      // This is a schema that is the target of a ref in an allOf chain.
      // If we entering the chain, we have to call the discriminator.
      // Otherwise we do the normal validation.
      if segment == "\$ref" and
          parent and parent.parent and parent.parent.segment == "allOf":
        // We are already in the chain.
        // Do the normal validation (by falling through).
      else if segment == "discriminator":
        // We are beginning the chain.
        // Do the normal validation (by falling through).
      else:
        // Use the discriminator.
        return schema_.all-of-discriminator.validate o
            --context=context
            --location=this
            --instance-pointer=instance-pointer
            --required-hierarchy-schema=schema_

    if not context.needs-annotations:
      // Check if one of our actions need annotation.
      action-needs-annotations := schema_.actions.any: | action/Action |
        action is AnnotationsApplicator
      if action-needs-annotations:
        // From now on all sub schemas will collect annotations.
        // That's almost certainly too much, as most AnnotationsApplicators only
        // need annotations for the current object, but this is still short cutting
        // a lot of work.
        context = context.with --needs-annotations=true
    result := SubResult this instance-pointer
    schema_.actions.do: | action/Action |
      action-result/SubResult := ?
      if action is AnnotationsApplicator:
        annotations-action := action as AnnotationsApplicator
        action-result = annotations-action.validate o
            --context=context
            --location=this
            --annotations=result.annotations
            --instance-pointer=instance-pointer
      else:
        action-result = action.validate o
            --context=context
            --location=this
            --instance-pointer=instance-pointer
      result.merge action-result
      if not context.needs-all-errors and not result.is-valid:
        return action-result

    return result

class InstantiatedSchemaBool extends InstantiatedSchema:
  constructor parent/InstantiatedSchema? segment/string schema/Schema:
    super.from-sub_ parent segment schema

  validate o/any --context/ValidationContext --instance-pointer/JsonPointer -> SubResult:
    result := SubResult this instance-pointer
    if not schema.json-value:
      result.fail-false
    return result


/**
A schema resource identifies a group of schemas.

It defines which vocabulary is used.
It resets the json-pointer.
It sets the URL for all contained schemas that are relative to the resource.
*/
class SchemaResource_:
  uri/UriReference
  vocabularies/Map  // The dialect of this schema resource.
  handled-keywords/Set  // The keywords handled by the vocabularies.

  constructor o/any --parent/Schema? --base-uri/UriReference? --build-context/BuildContext:
    id/string? := o is Map ? o.get "\$id" : null

    if not id and base-uri:
      id = base-uri.to-string
    else if not id:
      id = "urn:uuid:$(Uuid.uuid5 "json-schema" "$Time.now.ns-since-epoch")"
    // Empty fragments are allowed (but not recommended).
    // Trim them.
    id = id.trim --right "#"
    new-uri := UriReference.parse id
    if not new-uri.is-absolute:
      new-uri = new-uri.resolve --base=parent.schema-resource.uri
    new-uri = new-uri.normalize
    this.uri = new-uri

    if id and base-uri and new-uri != base-uri:
      // The resource was loaded with the base-uri, but it declares a different ID.
      // Remember the mapping.
      build-context.resource-uri-id-mapping[base-uri] = new-uri

    // Unless this is a schema with a "$schema" property that overrides the
    // dialect, these are the vocabularies we want to use:
    //  Inherit from parent if there is one, otherwise use the default ones.
    specified-schema := o is Map and o.get "\$schema"
    if specified-schema or not parent:
      meta-uri := specified-schema or build-context.default-vocabulary-uri
      dialect := DIALECTS_.get meta-uri
      if not dialect:
        meta-schema := build-context.resource-loader.load meta-uri
        if meta-schema is Map:
          dialect = meta-schema.get "\$vocabulary"
      vocabularies = {:}
      dialect.do: | vocabulary-uri/string required/bool |
        vocabulary := KNOWN-VOCABULARIES_.get vocabulary-uri
        if not vocabulary and required:
          throw "Unknown vocabulary: $vocabulary-uri"
        if vocabulary:
          vocabularies[vocabulary-uri] = vocabulary
    else:
      vocabularies = parent.schema-resource.vocabularies

    handled-keywords = {}
    vocabularies.do: | _ vocabulary/Vocabulary |
      handled-keywords.add-all vocabulary.keywords
