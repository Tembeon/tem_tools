/// Signature for callbacks that return a value of type [T].
///
/// Structurally identical to Flutter's `ValueGetter` from
/// `package:flutter/foundation.dart`. Dart typedefs are structural, so the
/// two are literally the same type: any function literal satisfies both,
/// and [ValueGetterX.or] works on either.
///
/// In Flutter projects, where importing this package together with Flutter
/// would make the name `ValueGetter` ambiguous, hide this one - the
/// extension keeps working on Flutter's `ValueGetter` because it is
/// declared on the function type, not on the name:
/// ```dart
/// import 'package:copy/copy.dart' hide ValueGetter;
/// import 'package:flutter/foundation.dart';
/// ```
typedef ValueGetter<T> = T Function();

extension ValueGetterX<T> on ValueGetter<T>? {
  /// {@template copy}
  /// Used to select one of two values,
  /// either the result of this function (if it exists) or [other].
  ///
  /// Typically used in `copyWith` constructions involving [ValueGetter]:
  ///
  /// ```dart
  ///   SomeState copyWith({
  ///     ValueGetter<StateType>? stateType,
  ///     ValueGetter<Entity?>? entity,
  ///     ValueGetter<Object?>? error,
  ///   }) => SomeState(
  ///     stateType: stateType.or(this.stateType),
  ///     entity: entity.or(this.entity),
  ///     error: error.or(this.error),
  ///   );
  /// ```
  /// {@endtemplate}
  T or(T other) => this == null ? other : this!();
}
