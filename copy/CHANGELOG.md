## 1.1.0

- Flutter interop via conditional export: in Flutter builds `ValueGetter`
  is re-exported from `package:flutter/foundation.dart` (same declaration,
  no compile-time ambiguity, no flutter dependency in this package); the
  local typedef is used elsewhere. Prior art: lrhn/listen_flutter.
  Caveat: the analyzer resolves the default branch, so IDEs may still
  report `ambiguous_import` when both packages are imported - use
  `import 'package:copy/copy.dart' hide ValueGetter;` to silence it.
- `or()` is now declared on the bare `T Function()?` type, making it
  typedef-agnostic (works with either `ValueGetter` and plain closures).
- Tests proving the extension applies to foreign identical typedefs and
  the bare function type.

## 1.0.0

- Initial version.
