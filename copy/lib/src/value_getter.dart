/// Signature for callbacks that return a value of type [T].
///
/// This declaration is used only outside Flutter. In Flutter builds
/// (when `dart:ui` is available) the library conditionally re-exports
/// Flutter's own `ValueGetter` from `package:flutter/foundation.dart`
/// instead, so both names refer to the same declaration and importing
/// this package together with Flutter causes no ambiguity.
///
/// The two are interchangeable either way: Dart typedefs are structural,
/// and both are `T Function()`.
typedef ValueGetter<T> = T Function();
