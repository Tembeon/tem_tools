## 1.1.0

- Documented Flutter interop: typedefs are structural, so `or()` works on
  Flutter's `ValueGetter` too - hide this package's typedef on collision
  (`import 'package:copy/copy.dart' hide ValueGetter;`). Conditional
  imports can detect Flutter (`if (dart.library.ui)`) but cannot pull in
  `package:flutter` from a pure Dart package, and all branches must expose
  the same API - so the structural approach is the right one.
- Tests proving the extension applies to foreign identical typedefs and
  the bare `T Function()` type.

## 1.0.0

- Initial version.
