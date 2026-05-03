# JSON Schema Tools

## Tests

Run with
```
git clone https://github.com/json-schema-org/JSON-Schema-Test-Suite.git
toit test.toit JSON-Schema-Test-Suite/remotes JSON-Schema-Test-Suite/tests/draft2020-12
```

Expected result: 1264/1267
Expected failures:
```
Running JSON-Schema-Test-Suite/tests/draft2020-12/multipleOf.json
  Running suite by small number
    Running test 0.0075 is multiple of 0.0001
      Test result: false - FAIL
  Running suite float division = inf
    Running test always invalid, but naive implementations may raise an overflow error
      Test result: true - FAIL
  Running suite small multiple of large integer
    Running test any integer is a multiple of 1e-8
      Test result: false - FAIL
```

