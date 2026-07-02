/// The extension is declared on the bare function type rather than the
/// `ValueGetter` typedef on purpose: typedefs are structural, so this
/// applies equally to this package's `ValueGetter`, Flutter's
/// `ValueGetter`, and any plain `T Function()`.
extension ValueGetterX<T> on T Function()? {
  /// {@template copy}
  /// Used to select one of two values,
  /// either the result of this function (if it exists) or [other].
  ///
  /// Typically used in `copyWith` constructions involving `ValueGetter`:
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
