/// {@template Json}
///
/// Json is a Map\<String, Object?\> used for parsing JSON responses from the server.
///
/// To get an instance of [Json] from [Map<String, Object?>], use the [Json] constructor or cast Map as Json.
/// ```dart
/// final json = Json(Map<String, Object?>.from(jsonDecode(response.body)));
/// ```
/// ```dart
/// final json = Map<String, Object?>.from(jsonDecode(response.body)) as Json;
/// ```
///
/// {@endtemplate}
extension type Json(Map<String, Object?> value) implements Map<String, Object?> {
  /// Get a value of type [T] from this [Json] using a shortcut.
  ///
  /// Usage example:
  /// ```dart
  /// final json = jsonDecode(response.body) as Json;
  ///
  /// int valueInt = json('id'); # type will be int, same as the variable type
  /// String? maybeValue = json('name'); # in this case will be String?
  /// ```
  ///
  /// If type [T] needs to be something else that should be parsed separately,
  /// use the [parse] function.
  T call<T>(String key, {T Function()? fallback}) {
    return switch (this[key]) {
      final T value => value,
      final Object? value =>
        fallback?.call() ??
            (throw ArgumentError('Invalid type of key "$key" — ${value.runtimeType}, expected $T', key)),
    };
  }

  /// Get a value of type [R] from json of type [T].
  /// * [R] — what should be returned in the end.
  /// * [T] — what the json at [key] is.
  ///
  /// Usage example:
  /// ```dart
  /// final json = jsonDecode(response.body) as Json;
  ///
  /// final MyEntity = json.parse('entity_object', fromJson: MyEntity.fromJson);
  /// ```
  R parse<T, R>(
    String key, {
    R Function()? fallback,
    required R Function(T json) fromJson,
  }) {
    final json = call<T?>(key);
    if (json is! T) {
      return (fallback ?? (throw ArgumentError('Invalid type of key $key — ${value.runtimeType}, expected $T', key)))
          .call();
    }

    return fromJson(json);
  }

  /// Get a value of type [R] from json of type [Json].
  /// * [R] — what should be returned in the end.
  /// * [key] — the key to get the value from.
  /// * [fallback] — function that will be called if the value is not found, by default throws [ArgumentError].
  /// * [fromJson] — function that will be used to parse the value.
  R parseJson<R>(String key, {R Function()? fallback, required R Function(Json json) fromJson}) =>
      parse<Json, R>(key, fallback: fallback, fromJson: fromJson);

  /// Get a list of values of type [R] from json of type [Json].
  /// * [R] — what should be returned in the end.
  /// * [key] — the key to get the value from.
  /// * [fallback] — function that will be called if the value is not found, by default throws [ArgumentError].
  /// * [fromJson] — function that will be used to parse the value.
  List<R> parseJsonList<R>(
    String key, {
    List<R> Function()? fallback,
    required List<R> Function(List<Json> json) fromJson,
  }) {
    final json = call<List<Object?>?>(key);
    if (json is! List<Object?>) {
      return (fallback ??
              (throw ArgumentError('Invalid type of key $key — ${value.runtimeType}, expected List<Object?>', key)))
          .call();
    }

    return fromJson(json.map((e) => Json(e! as Map<String, Object?>)).toList(growable: false));
  }

  /// Get a value of type [T] from nested json using path traversal.
  ///
  /// The path supports both dot notation and bracket notation for arrays.
  ///
  /// Usage examples:
  /// ```dart
  /// final json = Json({
  ///   'user': {
  ///     'profile': {
  ///       'name': 'John',
  ///       'age': 30
  ///     }
  ///   },
  ///   'users': [
  ///     {'name': 'Alice', 'tags': ['admin', 'user']},
  ///     {'name': 'Bob', 'tags': ['user']}
  ///   ]
  /// });
  ///
  /// // Dot notation for nested objects
  /// String name = json.path<String>('user.profile.name'); // 'John'
  /// int age = json.path<int>('user.profile.age'); // 30
  ///
  /// // Dot notation with index for arrays
  /// String firstName = json.path<String>('users.0.name'); // 'Alice'
  ///
  /// // Bracket notation for arrays (more intuitive)
  /// String secondName = json.path<String>('users[1].name'); // 'Bob'
  /// String tag = json.path<String>('users[0].tags[0]'); // 'admin'
  ///
  /// // With fallback for missing values
  /// String email = json.path<String>('user.email', fallback: () => 'no-email');
  ///
  /// // Custom separator
  /// String customPath = json.path<String>('user/profile/name', separator: '/');
  /// ```
  T path<T>(String path, {T Function()? fallback, String separator = '.'}) {
    // Normalize bracket notation to dot notation
    // users[0].name -> users.0.name
    // users[0].tags[1] -> users.0.tags.1
    final normalizedPath = path
        .replaceAll('[', separator)
        .replaceAll(']', '');

    final keys = normalizedPath.split(separator);
    Object? current = value;

    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];

      // Skip empty keys (from consecutive separators like ']..')
      if (key.isEmpty) continue;

      if (current == null) {
        return fallback?.call() ??
            (throw ArgumentError(
              'Path traversal failed at "${keys.take(i).join(separator)}": value is null',
              path,
            ));
      }

      if (current is Map<String, Object?>) {
        current = current[key];
      } else if (current is List<Object?>) {
        final index = int.tryParse(key);
        if (index == null || index < 0 || index >= current.length) {
          return fallback?.call() ??
              (throw ArgumentError(
                'Invalid array index "$key" at path "${keys.take(i).join(separator)}"',
                path,
              ));
        }
        current = current[index];
      } else {
        return fallback?.call() ??
            (throw ArgumentError(
              'Path traversal failed at "${keys.take(i).join(separator)}": expected Map or List, got ${current.runtimeType}',
              path,
            ));
      }
    }

    return switch (current) {
      final T typedValue => typedValue,
      final Object? value => fallback?.call() ??
          (throw ArgumentError(
            'Invalid type at path "$path" — ${value.runtimeType}, expected $T',
            path,
          )),
    };
  }
}
