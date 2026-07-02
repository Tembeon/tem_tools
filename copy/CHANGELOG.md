## 1.1.0

- Documented Flutter interop: typedefs are structural, so `or()` works on
  Flutter's `ValueGetter` too - hide this package's typedef on collision
  (`import 'package:copy/copy.dart' hide ValueGetter;`). A conditional
  import of Flutter is not possible for a pure Dart package (pub
  dependencies are unconditional) and is not needed.
- Tests proving the extension applies to foreign identical typedefs and
  the bare `T Function()` type.

## 1.0.0

- Initial version.
