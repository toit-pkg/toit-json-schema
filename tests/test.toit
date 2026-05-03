// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import cli
import encoding.json
import host.file
import host.directory

import json-schema
import json-schema.resource-loader as json-schema

import encoding.url

total-counter := 0
success-counter := 0
expected-fail-counter := 0
unexpected-succeed-counter := 0

class TestLoader extends json-schema.HttpResourceLoader:
  static LOCALHOST-PREFIX ::= "http://localhost:1234/"
  remote-path/string?

  constructor .remote-path:

  load url/string:
    if remote-path and url.starts-with LOCALHOST-PREFIX:
      local-path := url[LOCALHOST-PREFIX.size..]
      content := file.read-contents "$remote-path/$local-path"
      return json.decode content
    else:
      return super url

main args:
  cmd := cli.Command "test"
      --options=[
        cli.Option "expected-failures"
            --help="Path to a file with expected failures."
      ]
      --rest=[
        cli.Option "remote-path"
            --help="Path to the directory with remote resources."
            --type="directory"
            --required,
        cli.Option "tests"
            --help="Path to a directory containing tests."
            --type="directory-or-file"
            --required,
      ]
      --run=:: | invocation/cli.Invocation |
        run invocation
  cmd.run args

run invocation/cli.Invocation:
  remote-path/string := invocation["remote-path"]
  tests/string := invocation["tests"]

  expected-failures-path := invocation["expected-failures"]
  expected-failures/Map := ?
  if expected-failures-path:
    fail-contents := file.read-contents expected-failures-path
    expected-failures = json.decode fail-contents
  else:
    expected-failures = {:}

  resource-loader := TestLoader remote-path

  if file.is-file tests:
    run-test-file tests
        --resource-loader=resource-loader
        --expected-failures=expected-failures
  else:
    stream := directory.DirectoryStream tests
    while entry := stream.next:
      file-path := "$tests/$entry"
      if file.is-file file-path:
        run-test-file file-path
            --resource-loader=resource-loader
            --expected-failures=expected-failures
    stream.close
  print "Success: $success-counter/$total-counter ($expected-fail-counter expected failures)"
  if unexpected-succeed-counter > 0:
    print "Unexpected successes: $unexpected-succeed-counter"

  if unexpected-succeed-counter > 0 or (success-counter + expected-fail-counter) < total-counter:
    exit 1
  else:
    exit 0

run-test-file file-path/string
    --resource-loader/json-schema.ResourceLoader
    --expected-failures/Map
:
  test-json := json.decode (file.read-contents file-path)
  already-printed := false
  run-tests test-json
      --resource-loader=resource-loader
      --expected-failures=(expected-failures.get file-path or {:})
      --print-header=:
        if not already-printed:
          already-printed = true
          print "Running $file-path"

run-tests test-json/List
    --resource-loader/json-schema.ResourceLoader
    --expected-failures/Map
    [--print-header]:
  test-json.do: | entry/Map |
    suite-expected-failures := expected-failures.get entry["description"] or {:}
    total-counter += entry["tests"].size

    already-printed-suite := false
    print-suite := :
      if not already-printed-suite:
        already-printed-suite = true
        print-header.call
        print "  Running suite '$entry["description"]'"
    schema/json-schema.JsonSchema? := null
    exception := catch --trace:
      schema = json-schema.build entry["schema"] --resource-loader=resource-loader
    if exception:
      print-suite.call
      print "    Suite schema construction failed: $exception"
      continue.do
    else:
    entry["tests"].do: | test/Map |
      expected-to-fail := suite-expected-failures.get test["description"] --if-absent=: false
      result/json-schema.Result? := null
      test-exception := catch --trace:
        result = schema.validate test["data"] --collect-annotations --no-collect-all-errors
      is-valid := result ? result.is-valid : false
      if test-exception: is-valid = not test["valid"]
      if test["valid"] == is-valid: success-counter++
      if test["valid"] != is-valid:
        print-suite.call
        print "    Running test '$test["description"]'"
        print "      Test result: $is-valid - $(test["valid"] == result ? "OK" : "FAIL")"
        // json-value := result.to-json --structure-kind=json-schema.Result.STRUCTURE-BASIC
        // print (json.stringify json-value)
        if expected-to-fail:
          print "      Expected to fail"
          expected-fail-counter++
      else if expected-to-fail:
        print-suite.call
        print "    Running test $test["description"]"
        print "      Test unexpectedly succeeded"
        unexpected-succeed-counter++
