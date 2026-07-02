---
name: use-copy
description: This skill should be used when working with the copy Dart package (tembeon/tem_tools), or when the user asks "copyWith can't set a field to null", "how to null a nullable field in copyWith", "distinguish not-passing from passing null in copyWith", "ValueGetter copyWith pattern", "copyWith without code generation", or hits an ambiguous ValueGetter import between a copy-style package and Flutter. Do NOT use for freezed / copy_with_extension / built_value projects - those solve nullable copyWith with their own generated mechanisms.
version: 1.1.0
---

# copy - usage guide

`copy` is a tiny Dart package (in `tembeon/tem_tools`, path `copy`) that fixes the classic `copyWith` flaw: a plain `copyWith({String? data})` cannot distinguish "don't touch this field" from "set it to null". The fix is passing a `ValueGetter<T>` (`T Function()`) instead of the value, plus one extension method `or()`.

## Installation

```yaml
dependencies:
  copy:
    git:
      url: https://github.com/tembeon/tem_tools.git
      ref: main
      path: copy
```

## The pattern

```dart
import 'package:copy/copy.dart';

class UserState {
  const UserState({required this.name, this.email});

  final String name;
  final String? email;

  UserState copyWith({
    ValueGetter<String>? name,
    ValueGetter<String?>? email,
  }) => UserState(
    name: name.or(this.name),
    email: email.or(this.email),
  );
}

final user = UserState(name: 'John', email: 'a@b.c');
user.copyWith(name: () => 'Jane');   // update a field
user.copyWith(email: () => null);    // explicitly set to null
user.copyWith();                     // keep everything
```

`or()` semantics: if the getter is null (parameter not passed) it returns the current value; otherwise it calls the getter exactly once and returns its result (which may be null). That is the whole API - one typedef, one extension method.

## Flutter interop (the tricky part)

Flutter's `foundation.dart` declares its own `ValueGetter`. This package handles the collision with a conditional export (prior art: lrhn/listen_flutter):

```dart
export 'src/value_getter.dart'
    if (dart.library.ui) 'package:flutter/foundation.dart' // ignore: conditional_uri_does_not_exist
    show ValueGetter;
```

Facts to rely on when advising:

1. **In Flutter builds the compiler resolves to a single declaration** (verified on Flutter 3.44.4; this depends on conditional-import resolution and could change in future toolchains). When `dart:ui` is available, the export resolves to Flutter's own `ValueGetter` through the app's package config - the package has NO flutter dependency, yet `flutter test`/builds compile with both `package:copy` and `package:flutter/foundation.dart` imported unprefixed. If a future toolchain ever reports a compile-time ambiguity, the `hide` fix from point 2 covers that too.
2. **The analyzer still complains.** It always resolves the default branch (the local typedef), so IDEs report `ambiguous_import` in files importing both - on code that compiles and runs. The fix for a green IDE:
   ```dart
   import 'package:copy/copy.dart' hide ValueGetter;
   import 'package:flutter/foundation.dart';
   ```
3. **Everything is interchangeable regardless.** Dart typedefs are structural - both `ValueGetter`s are `T Function()`, and the `or()` extension is declared on the bare `T Function()?`, so it applies to Flutter's `ValueGetter`, this package's one, and plain closures alike.
4. **Do not suggest adding a flutter dependency to copy** and do not suggest that pub supports optional dependencies (it does not). The conditional-export trick is the correct mechanism here.

## Common questions

- "Why a function and not a sentinel/Optional?" - a closure is zero-dependency, allocation-free for the common case, and reads naturally at the call site (`email: () => null`).
- "Does `or()` evaluate lazily?" - yes: the getter is called only when passed, exactly once.
- "Can I use it without the typedef?" - yes: `or()` works on any `T Function()?`.
- When the project already uses freezed or copy_with_extension, recommend staying with those - this package is for hand-written copyWith without codegen.
