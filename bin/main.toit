// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import cli
import encoding.json
import host.directory
import host.file
import json-schema
import json-schema.gen as schema-gen

main args/List:
  command := cli.Command "gen-toit"
      --help="Generate Toit code from a JSON schema"
      --options=[
        cli.Option "out" --short-name="o"
            --help="Output directory for the generated Toit code"
            --type="directory"
            --required,
        cli.Option "module" --short-name="m"
            --help="Module filename to generate inside the output directory"
            --default="schema.toit",
      ]
      --rest=[
        cli.Option "schema"
          --help="Path to the JSON schema file"
          --type="file"
          --required
      ]
      --run=:: | invocation/cli.Invocation |
        gen invocation
  command.run args

gen invocation/cli.Invocation:
  schema-path := invocation["schema"]
  output-dir := invocation["out"]
  module := invocation["module"]

  contents := file.read-contents schema-path
  decoded := json.decode contents
  schema := json-schema.build decoded

  print "Generating Toit code from schema '$schema-path' into '$output-dir/$module'"

  files := schema-gen.gen [schema] --module=module
  directory.mkdir --recursive output-dir
  files.do: | name/string code/string |
    path := "$output-dir/$name"
    file.write-contents --path=path code
    print "Wrote $path"
