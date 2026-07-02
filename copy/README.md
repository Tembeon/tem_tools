# Copy Extension

A Dart package that simplifies the `copyWith` pattern for immutable state objects, eliminating boilerplate when updating nullable fields.

## Features

- **Simplified copyWith** - Distinguish between "not updating a field" and "setting a field to null"
- **Type-safe** - Leverages Dart's generic type system
- **Zero boilerplate** - No code generation required
- **Nullable field support** - Easily set fields to null in copyWith methods
- **Lightweight** - Single extension method, no dependencies

## Getting started

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  copy:
    git:
      url: https://github.com/tembeon/tem_tools.git
      ref: main
      path: copy
```

Import the package:

```dart
import 'package:copy/copy.dart';
```

## Usage

### The Problem

Traditional copyWith methods can't distinguish between "don't update this field" and "set this field to null":

```dart
class State {
  final String? data;

  State({this.data});

  // ❌ Can't set data to null using this approach
  State copyWith({String? data}) => State(
    data: data ?? this.data,  // Can't pass null explicitly
  );
}
```

### The Solution

Use `ValueGetter` with the `or()` extension method:

```dart
class State {
  final String? data;

  State({this.data});

  // ✅ Can now set data to null
  State copyWith({ValueGetter<String?>? data}) => State(
    data: data.or(this.data),
  );
}

// Usage
final state = State(data: 'hello');
final cleared = state.copyWith(data: () => null);  // Explicitly set to null
final unchanged = state.copyWith();                 // Keep existing value
```

### Complete Example

```dart
import 'package:copy/copy.dart';

class UserState {
  final String name;
  final int age;
  final String? email;
  final List<String>? tags;

  UserState({
    required this.name,
    required this.age,
    this.email,
    this.tags,
  });

  UserState copyWith({
    ValueGetter<String>? name,
    ValueGetter<int>? age,
    ValueGetter<String?>? email,
    ValueGetter<List<String>?>? tags,
  }) => UserState(
    name: name.or(this.name),
    age: age.or(this.age),
    email: email.or(this.email),
    tags: tags.or(this.tags),
  );
}

void main() {
  final user = UserState(
    name: 'John',
    age: 30,
    email: 'john@example.com',
    tags: ['developer', 'dart'],
  );

  // Update only the name
  final renamed = user.copyWith(name: () => 'Jane');

  // Clear the email (set to null)
  final noEmail = user.copyWith(email: () => null);

  // Update multiple fields
  final updated = user.copyWith(
    age: () => 31,
    tags: () => ['developer', 'dart', 'flutter'],
  );
}
```

## Flutter interop

Flutter's `foundation.dart` declares its own `ValueGetter`. This package
uses a conditional export so that in Flutter builds both names refer to the
same declaration (prior art:
[lrhn/listen_flutter](https://github.com/lrhn/listen_flutter)):

```dart
export 'src/value_getter.dart'
    if (dart.library.ui) 'package:flutter/foundation.dart' // ignore: conditional_uri_does_not_exist
    show ValueGetter;
```

When compiled by Flutter (`dart:ui` available), the export resolves to
Flutter's own `ValueGetter` through the app's package config - no `flutter`
dependency needed in this package, and no ambiguity at compile time.
Outside Flutter the local typedef is used. Either way the types are
interchangeable: Dart typedefs are structural, both are `T Function()`,
and the `or()` extension is declared on the bare function type.

One caveat, verified empirically: the **analyzer always resolves the
default branch** (the local typedef), so an IDE may still report
`ambiguous_import` in files importing both this package and Flutter -
even though the code compiles and runs. Silence it the usual way:

```dart
import 'package:copy/copy.dart' hide ValueGetter;
import 'package:flutter/foundation.dart';

// or() still works on Flutter's ValueGetter
state.copyWith(data: () => null);
```

## How it works

The package provides a simple extension on nullable `ValueGetter<T>?`:

```dart
typedef ValueGetter<T> = T Function();

extension ValueGetterX<T> on ValueGetter<T>? {
  T or(T other) => this == null ? other : this!();
}
```

When you call `.or(defaultValue)`:
- If the ValueGetter is `null` → returns the default value (field unchanged)
- If the ValueGetter exists → calls it and returns the result (field updated, possibly to null)
