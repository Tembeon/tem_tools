## 1.1.0

Fixed:

- `parse`, `parseJson` and `parseJsonList` now honor `fallback` when the
  value has the wrong type (previously they threw even with a fallback
  provided).
- Error messages report the type of the offending value instead of the
  type of the whole map.
- `parseJsonList` no longer crashes with a raw cast `TypeError` on lists
  containing null or non-object elements: it throws an `ArgumentError`
  naming the element index, or uses the `fallback`.

Added:

- `Json.decode(source)` and `Json.decodeList(source)` - decode straight
  from a JSON string without the `jsonDecode` + cast dance.
- `parseList(key, fromJson: ...)` - per-element list parsing without the
  `.map().toList()` boilerplate of `parseJsonList`.
- `listOf<T>(key)` - typed lists of primitives; solves the
  `json<List<String>>('tags')` trap where `jsonDecode` produces
  `List<dynamic>` that never matches a reified `List<String>`.

## 1.0.0

- Initial version.
