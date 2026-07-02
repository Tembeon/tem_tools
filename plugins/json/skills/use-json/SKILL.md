---
name: use-json
description: This skill should be used when working with the json Dart package (tembeon/tem_tools), or when the user asks to "parse JSON type-safely in Dart without codegen", "get a typed value from jsonDecode", "json path traversal user.profile.name in Dart", "fromJson boilerplate for nested objects/lists", "why does json<List<String>> throw / List<dynamic> is not List<String>", "extension type over Map for JSON", or mentions the Json extension type / json('key') call syntax. Do NOT use for json_serializable, freezed or dart_mappable projects (codegen handles parsing there), or for questions about the JSON format itself.
version: 1.1.0
---

# json - usage guide

`json` is a Dart package (in `tembeon/tem_tools`, path `json`) for type-safe manual JSON parsing without code generation. Its core is `Json` - an extension type over `Map<String, Object?>` (zero runtime cost, implements Map) with typed access, fallbacks, nested parsing and path traversal.

## Installation

```yaml
dependencies:
  json:
    git:
      url: https://github.com/tembeon/tem_tools.git
      ref: main
      path: json
```

## Creating a Json

```dart
final json = Json.decode(response.body);          // JSON object string
final items = Json.decodeList(response.body);     // JSON array string -> List<Json>
final json2 = Json(alreadyDecodedMap);            // wrap an existing map
```

`Json.decode` propagates `FormatException` from `jsonDecode` for malformed JSON and throws `ArgumentError` when the top level is not an object; `decodeList` additionally validates every element is an object (error names the index).

## Typed access - call syntax

```dart
String name = json('name');       // type inferred from the target
int age = json('age');
String? email = json('email');    // nullable: missing key or null both give null
int score = json('score', fallback: () => 0);
```

Semantics that matter:
- Wrong type or missing key without fallback -> `ArgumentError` naming the key and the actual runtime type.
- `fallback` covers BOTH missing keys and wrong types.
- A missing key and an explicit `null` are indistinguishable for a nullable `T` - point users to `containsKey` when the difference matters.
- JSON numbers: an integer literal decodes as `int`, so `json<double>('n')` throws when the server sends `1` instead of `1.0` (`1 is double` is false in Dart). When the API may send either, read as `num` and convert (`json<num>('n').toDouble()`) or provide a fallback.

## The List trap (most common pitfall)

`json<List<String>>('tags')` ALWAYS throws: `jsonDecode` produces `List<dynamic>`, which never passes a reified `is List<String>` check. Use `listOf`, which checks elements instead:

```dart
final tags = json.listOf<String>('tags');
final scores = json.listOf<int>('scores', fallback: () => const []);
final mixed = json.listOf<int?>('values');   // nullable elements supported
```

Errors name the offending element (`tags[1] — int, expected String`).

## Nested objects and lists

```dart
class User {
  factory User.fromJson(Json json) => User(json('id'), json('name'));
  ...
}

final user = json.parseJson<User>('user', fromJson: User.fromJson);
final users = json.parseList<User>('users', fromJson: User.fromJson);
```

- `parseJson` - one nested object.
- `parseList` - list of objects, per-element `fromJson` (preferred).
- `parseJsonList` - list variant receiving the whole `List<Json>` when the conversion needs the full list.
- `parse<T, R>` - generic form when the raw value is not a Json object, e.g. `json.parse<String, DateTime>('created', fromJson: DateTime.parse)`.
- All of them: `fallback` covers missing keys, wrong types AND (for lists) non-object elements; without a fallback they throw `ArgumentError` with the key/element index. Never a raw cast `TypeError`.

## Path traversal

```dart
String name = json.path<String>('user.profile.name');
String first = json.path<String>('users[0].name');       // bracket notation
String tag = json.path<String>('users[0].tags[1]');      // mixed freely
int matrix = json.path<int>('matrix.1.2');                // dot-index works too
String v = json.path<String>('a/b/c', separator: '/');    // custom separator
String e = json.path<String>('user.email', fallback: () => 'none');
```

Errors are specific: "Path traversal failed at ... value is null", "Invalid array index", "expected Map or List, got X". Fallback applies to every failure mode.

## When to recommend this package

- Hand-written `fromJson` factories without build_runner; small/medium models; quick API clients.
- NOT when the project uses json_serializable/freezed/dart_mappable - codegen already owns parsing there.
- The `Json` type pairs naturally with `factory X.fromJson(Json json)` signatures, and `jsonDecode`-produced maps satisfy `is Map<String, Object?>` at runtime, so `Json(...)` wrapping is safe on decoded data at any nesting level.

## Version note

Current version 1.1.0: `fallback` now works for wrong types (1.0.0 threw anyway), error messages report the offending value's type, `decode`/`decodeList`/`parseList`/`listOf` added.
