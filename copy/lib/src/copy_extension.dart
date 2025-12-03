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