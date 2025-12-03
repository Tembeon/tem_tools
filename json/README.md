# Json Extension Type

A lightweight and type-safe JSON parsing class for Dart that provides convenient methods for accessing and transforming JSON data.

## Features

- **Type-safe access** with automatic type inference
- **Fallback values** for missing or invalid data
- **Nested object parsing** with custom fromJson functions
- **List parsing** with type transformation
- **Path traversal** using dot notation (`user.profile.name`) and bracket notation (`users[0].tags[1]`)
- **Custom separators** for path traversal
- **Map interface** - works with all standard Map methods
- **Zero overhead** - extension type wraps Map without runtime cost

## Getting started

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  json:
    git:
      url: https://github.com/tembeon/tem_tools.git
      ref: main
      path: json
```

Import the package:

```dart
import 'package:json/json.dart';
import 'dart:convert';
```

## Usage

### Basic type inference

```dart
final json = Json(jsonDecode(response.body));

String name = json('name');        // Automatic type inference
int age = json('age');
bool isActive = json('isActive');
```

### With fallback values

```dart
String email = json('email', fallback: () => 'no-email@example.com');
int score = json('score', fallback: () => 0);
```

### Path traversal

```dart
// Dot notation
String city = json.path<String>('address.city');

// Bracket notation for arrays
String firstName = json.path<String>('users[0].name');
String tag = json.path<String>('users[0].tags[1]');
```

### Parsing custom objects

```dart
class User {
  final String name;
  final int age;

  User({required this.name, required this.age});

  factory User.fromJson(Json json) => User(
    name: json('name'),
    age: json('age'),
  );
}

final user = json.parseJson<User>('user', fromJson: User.fromJson);
```

### Parsing lists of objects

```dart
final users = json.parseJsonList<User>(
  'users',
  fromJson: (list) => list.map((j) => User.fromJson(j)).toList(),
);
```

## Full Example

For a comprehensive demonstration of all features, see the [example](example/json_example.dart) which includes:

- All parsing methods (call, parse, parseJson, parseJsonList, path)
- Fallback handling
- Custom transformations
- Nested data structures
- Array indexing with both notations
- Map interface usage

Run the example:

```bash
dart run example/json_example.dart
```
