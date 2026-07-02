import 'dart:convert';

/// {@template Json}
///
/// Json is a Map\<String, Object?\> used for parsing JSON responses from the server.
///
/// To get an instance of [Json], use [Json.decode] for a raw string,
/// the [Json] constructor for an already decoded map, or cast a Map as Json.
/// ```dart
/// final json = Json.decode(response.body);
/// ```
/// ```dart
/// final json = Json(Map<String, Object?>.from(jsonDecode(response.body)));
/// ```
/// ```dart
/// final json = Map<String, Object?>.from(jsonDecode(response.body)) as Json;
/// ```
///
/// {@endtemplate}
extension type Json(Map<String, Object?> value)
    implements Map<String, Object?> {
  /// Decodes a JSON string into a [Json].
  ///
  /// Throws a [FormatException] for malformed JSON and an [ArgumentError]
  /// when the top-level value is not an object.
  ///
  /// ```dart
  /// final json = Json.decode(response.body);
  /// ```
  static Json decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw ArgumentError(
        'Expected a JSON object at the top level, got ${decoded.runtimeType}',
        'source',
      );
    }
    return Json(decoded);
  }

  /// Decodes a JSON string whose top-level value is an array of objects
  /// into a `List<Json>`.
  ///
  /// Throws a [FormatException] for malformed JSON and an [ArgumentError]
  /// when the top-level value is not an array or an element is not an object.
  ///
  /// ```dart
  /// final items = Json.decodeList(response.body);
  /// final users = items.map(User.fromJson).toList();
  /// ```
  static List<Json> decodeList(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List<Object?>) {
      throw ArgumentError(
        'Expected a JSON array at the top level, got ${decoded.runtimeType}',
        'source',
      );
    }
    final result = <Json>[];
    for (var i = 0; i < decoded.length; i++) {
      final element = decoded[i];
      if (element is! Map<String, Object?>) {
        throw ArgumentError(
          'Invalid element at index $i — ${element.runtimeType}, '
              'expected a JSON object',
          'source',
        );
      }
      result.add(Json(element));
    }
    return result;
  }

  /// Get a value of type [T] from this [Json] using a shortcut.
  ///
  /// Usage example:
  /// ```dart
  /// final json = Json.decode(response.body);
  ///
  /// int valueInt = json('id'); // type will be int, same as the variable type
  /// String? maybeValue = json('name'); // in this case will be String?
  /// ```
  ///
  /// Note: a missing key and an explicit `null` value are indistinguishable —
  /// both return null for a nullable [T]. Use `containsKey` when the
  /// difference matters.
  ///
  /// If type [T] needs to be something else that should be parsed separately,
  /// use the [parse] function. For typed lists of primitives use [listOf].
  T call<T>(String key, {T Function()? fallback}) {
    return switch (this[key]) {
      final T value => value,
      final Object? value =>
        fallback?.call() ??
            (throw ArgumentError(
              'Invalid type of key "$key" — ${value.runtimeType}, expected $T',
              key,
            )),
    };
  }

  /// Get a value of type [R] from json of type [T].
  /// * [R] — what should be returned in the end.
  /// * [T] — what the json at [key] is.
  /// * [fallback] — called when the value is missing or has the wrong type;
  ///   without it an [ArgumentError] is thrown.
  ///
  /// Usage example:
  /// ```dart
  /// final json = Json.decode(response.body);
  ///
  /// final entity = json.parse('entity_object', fromJson: MyEntity.fromJson);
  /// ```
  R parse<T, R>(
    String key, {
    R Function()? fallback,
    required R Function(T json) fromJson,
  }) {
    final raw = this[key];
    if (raw is T) {
      return fromJson(raw);
    }
    if (fallback != null) {
      return fallback();
    }
    throw ArgumentError(
      'Invalid type of key "$key" — ${raw.runtimeType}, expected $T',
      key,
    );
  }

  /// Get a value of type [R] from json of type [Json].
  /// * [R] — what should be returned in the end.
  /// * [key] — the key to get the value from.
  /// * [fallback] — called when the value is missing or has the wrong type;
  ///   without it an [ArgumentError] is thrown.
  /// * [fromJson] — function that will be used to parse the value.
  R parseJson<R>(
    String key, {
    R Function()? fallback,
    required R Function(Json json) fromJson,
  }) => parse<Json, R>(key, fallback: fallback, fromJson: fromJson);

  /// Get a list of values of type [R] from json of type [Json],
  /// converting each element with [fromJson].
  /// * [R] — the element type of the resulting list.
  /// * [key] — the key to get the list from.
  /// * [fallback] — called when the value is missing, is not a list, or an
  ///   element is not an object; without it an [ArgumentError] is thrown.
  ///
  /// ```dart
  /// final users = json.parseList('users', fromJson: User.fromJson);
  /// ```
  List<R> parseList<R>(
    String key, {
    List<R> Function()? fallback,
    required R Function(Json json) fromJson,
  }) => parseJsonList<R>(
    key,
    fallback: fallback,
    fromJson: (list) => list.map(fromJson).toList(growable: false),
  );

  /// Get a list of values of type [R] from json of type [Json],
  /// converting the whole list with [fromJson].
  ///
  /// Prefer [parseList] when converting element by element.
  /// * [R] — the element type of the resulting list.
  /// * [key] — the key to get the list from.
  /// * [fallback] — called when the value is missing, is not a list, or an
  ///   element is not an object; without it an [ArgumentError] is thrown.
  /// * [fromJson] — function that will be used to parse the list.
  List<R> parseJsonList<R>(
    String key, {
    List<R> Function()? fallback,
    required List<R> Function(List<Json> json) fromJson,
  }) {
    final raw = this[key];
    if (raw is! List<Object?>) {
      if (fallback != null) {
        return fallback();
      }
      throw ArgumentError(
        'Invalid type of key "$key" — ${raw.runtimeType}, expected List',
        key,
      );
    }

    final jsonList = <Json>[];
    for (var i = 0; i < raw.length; i++) {
      final element = raw[i];
      if (element is! Map<String, Object?>) {
        if (fallback != null) {
          return fallback();
        }
        throw ArgumentError(
          'Invalid element at "$key[$i]" — ${element.runtimeType}, '
          'expected a JSON object',
          key,
        );
      }
      jsonList.add(Json(element));
    }

    return fromJson(jsonList);
  }

  /// Get a typed list of primitives (String, int, double, bool...) at [key].
  ///
  /// Solves the `List<dynamic>` trap: `json<List<String>>('tags')` always
  /// throws because `jsonDecode` produces `List<dynamic>`, which is not a
  /// `List<String>` at runtime. This method checks each element instead:
  ///
  /// ```dart
  /// final tags = json.listOf<String>('tags');
  /// final scores = json.listOf<int>('scores', fallback: () => const []);
  /// ```
  ///
  /// [fallback] is called when the value is missing, is not a list, or an
  /// element has the wrong type; without it an [ArgumentError] is thrown.
  List<T> listOf<T>(String key, {List<T> Function()? fallback}) {
    final raw = this[key];
    if (raw is! List<Object?>) {
      if (fallback != null) {
        return fallback();
      }
      throw ArgumentError(
        'Invalid type of key "$key" — ${raw.runtimeType}, expected List',
        key,
      );
    }

    final result = <T>[];
    for (var i = 0; i < raw.length; i++) {
      final element = raw[i];
      if (element is! T) {
        if (fallback != null) {
          return fallback();
        }
        throw ArgumentError(
          'Invalid element at "$key[$i]" — ${element.runtimeType}, '
          'expected $T',
          key,
        );
      }
      result.add(element);
    }
    return result;
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
    final normalizedPath = path.replaceAll('[', separator).replaceAll(']', '');

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
      final Object? value =>
        fallback?.call() ??
            (throw ArgumentError(
              'Invalid type at path "$path" — ${value.runtimeType}, expected $T',
              path,
            )),
    };
  }
}
