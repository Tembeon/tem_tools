import 'dart:convert';

import 'package:json/json.dart';
import 'package:test/test.dart';

void main() {
  group('Json extension type', () {
    group('call() method', () {
      test('should return correct type from json', () {
        final json = Json({'id': 123, 'name': 'John', 'active': true});

        expect(json<int>('id'), equals(123));
        expect(json<String>('name'), equals('John'));
        expect(json<bool>('active'), equals(true));
      });

      test('should return nullable value', () {
        final json = Json({'name': 'John', 'email': null});

        expect(json<String>('name'), equals('John'));
        expect(json<String?>('email'), isNull);
      });

      test('should throw ArgumentError for invalid type', () {
        final json = Json({'id': '123'});

        expect(
          () => json<int>('id'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid type of key "id"'),
          )),
        );
      });

      test('should use fallback when provided for invalid type', () {
        final json = Json({'id': '123'});

        expect(json<int>('id', fallback: () => 0), equals(0));
      });

      test('should throw ArgumentError for missing key', () {
        final json = Json({'name': 'John'});

        expect(
          () => json<int>('id'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should use fallback for missing key', () {
        final json = Json({'name': 'John'});

        expect(json<int>('id', fallback: () => -1), equals(-1));
      });
    });

    group('parse() method', () {
      test('should parse custom object from json', () {
        final json = Json({
          'user': {'id': 1, 'name': 'Alice'}
        });

        final user = json.parse<Json, User>(
          'user',
          fromJson: (json) => User(json<int>('id'), json<String>('name')),
        );

        expect(user.id, equals(1));
        expect(user.name, equals('Alice'));
      });

      test('should throw ArgumentError for invalid json type', () {
        final json = Json({'user': 'invalid'});

        expect(
          () => json.parse<Json, User>(
            'user',
            fromJson: (json) => User(json<int>('id'), json<String>('name')),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw when json type is invalid even with fallback', () {
        final json = Json({'user': 'invalid'});

        // The call() method throws before fallback can be used
        expect(
          () => json.parse<Json, User>(
            'user',
            fallback: () => User(0, 'Unknown'),
            fromJson: (json) => User(json<int>('id'), json<String>('name')),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should work with nested json objects', () {
        final json = Json({
          'address': {'street': 'Main St', 'number': 123}
        });

        final address = json.parse<Json, Address>(
          'address',
          fromJson: (json) => Address(json<String>('street'), json<int>('number')),
        );

        expect(address.street, equals('Main St'));
        expect(address.number, equals(123));
      });
    });

    group('parseJson() method', () {
      test('should parse nested Json object', () {
        final json = Json({
          'user': {'id': 42, 'name': 'Bob'}
        });

        final user = json.parseJson<User>(
          'user',
          fromJson: (json) => User(json<int>('id'), json<String>('name')),
        );

        expect(user.id, equals(42));
        expect(user.name, equals('Bob'));
      });

      test('should throw ArgumentError for non-Json type', () {
        final json = Json({'user': 'not-a-json'});

        expect(
          () => json.parseJson<User>(
            'user',
            fromJson: (json) => User(json('id'), json('name')),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw for invalid type even with fallback', () {
        final json = Json({'user': 'not-a-json'});

        // The call() method throws before fallback can be used
        expect(
          () => json.parseJson<User>(
            'user',
            fallback: () => User(-1, 'Default'),
            fromJson: (json) => User(json('id'), json('name')),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should work with deeply nested Json', () {
        final json = Json({
          'data': {
            'user': {'id': 100, 'name': 'Charlie'}
          }
        });

        final data = json.parseJson<DataWrapper>(
          'data',
          fromJson: (json) => DataWrapper(
            json.parseJson<User>(
              'user',
              fromJson: (userJson) => User(
                userJson('id'),
                userJson('name'),
              ),
            ),
          ),
        );

        expect(data.user.id, equals(100));
        expect(data.user.name, equals('Charlie'));
      });
    });

    group('parseJsonList() method', () {
      test('should parse list of Json objects', () {
        final json = Json({
          'users': [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
            {'id': 3, 'name': 'Charlie'},
          ]
        });

        final users = json.parseJsonList<User>(
          'users',
          fromJson: (jsonList) => jsonList
              .map((json) => User(json('id'), json('name')))
              .toList(),
        );

        expect(users.length, equals(3));
        expect(users[0].id, equals(1));
        expect(users[0].name, equals('Alice'));
        expect(users[1].id, equals(2));
        expect(users[1].name, equals('Bob'));
        expect(users[2].id, equals(3));
        expect(users[2].name, equals('Charlie'));
      });

      test('should return empty list for empty array', () {
        final json = Json({'users': <Object?>[]});

        final users = json.parseJsonList<User>(
          'users',
          fromJson: (jsonList) => jsonList
              .map((json) => User(json('id'), json('name')))
              .toList(),
        );

        expect(users, isEmpty);
      });

      test('should throw ArgumentError for non-list type', () {
        final json = Json({'users': 'not-a-list'});

        expect(
          () => json.parseJsonList<User>(
            'users',
            fromJson: (jsonList) => jsonList
                .map((json) => User(json('id'), json('name')))
                .toList(),
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('expected List<Object?>'),
          )),
        );
      });

      test('should throw for invalid type even with fallback', () {
        final json = Json({'users': 'not-a-list'});

        // The call() method throws before fallback can be used
        expect(
          () => json.parseJsonList<User>(
            'users',
            fallback: () => <User>[],
            fromJson: (jsonList) => jsonList
                .map((json) => User(json('id'), json('name')))
                .toList(),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should parse complex nested structures', () {
        final json = Json({
          'teams': [
            {
              'name': 'Team A',
              'members': [
                {'id': 1, 'name': 'Alice'},
                {'id': 2, 'name': 'Bob'},
              ]
            },
            {
              'name': 'Team B',
              'members': [
                {'id': 3, 'name': 'Charlie'},
              ]
            },
          ]
        });

        final teams = json.parseJsonList<Team>(
          'teams',
          fromJson: (jsonList) => jsonList
              .map((json) => Team(
                    json('name'),
                    json.parseJsonList<User>(
                      'members',
                      fromJson: (membersList) => membersList
                          .map((memberJson) => User(
                                memberJson('id'),
                                memberJson('name'),
                              ))
                          .toList(),
                    ),
                  ))
              .toList(),
        );

        expect(teams.length, equals(2));
        expect(teams[0].name, equals('Team A'));
        expect(teams[0].members.length, equals(2));
        expect(teams[1].name, equals('Team B'));
        expect(teams[1].members.length, equals(1));
      });
    });

    group('Json constructor and casting', () {
      test('should create Json from Map', () {
        final map = {'id': 1, 'name': 'Test'};
        final json = Json(map);

        expect(json<int>('id'), equals(1));
        expect(json<String>('name'), equals('Test'));
      });

      test('should cast Map as Json', () {
        final map = <String, Object?>{'id': 1, 'name': 'Test'};
        final json = map as Json;

        expect(json<int>('id'), equals(1));
        expect(json<String>('name'), equals('Test'));
      });

      test('should work with jsonDecode', () {
        const jsonString = '{"id": 123, "name": "John", "active": true}';
        final json = Json(Map<String, Object?>.from(jsonDecode(jsonString)));

        expect(json<int>('id'), equals(123));
        expect(json<String>('name'), equals('John'));
        expect(json<bool>('active'), equals(true));
      });
    });

    group('Json implements Map', () {
      test('should support Map operations', () {
        final json = Json({'id': 1, 'name': 'Test'});

        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('missing'), isFalse);
        expect(json.keys, contains('id'));
        expect(json.values, contains(1));
        expect(json.length, equals(2));
      });

      test('should support Map modification', () {
        final json = Json({'id': 1});

        json['name'] = 'Test';
        expect(json<String>('name'), equals('Test'));

        json.remove('id');
        expect(json.containsKey('id'), isFalse);
      });
    });

    group('path() method', () {
      test('should traverse simple nested path', () {
        final json = Json({
          'user': {
            'name': 'Alice',
            'age': 25,
          }
        });

        expect(json.path<String>('user.name'), equals('Alice'));
        expect(json.path<int>('user.age'), equals(25));
      });

      test('should traverse deeply nested path', () {
        final json = Json({
          'data': {
            'user': {
              'profile': {
                'personal': {
                  'firstName': 'John',
                  'lastName': 'Doe',
                }
              }
            }
          }
        });

        expect(json.path<String>('data.user.profile.personal.firstName'), equals('John'));
        expect(json.path<String>('data.user.profile.personal.lastName'), equals('Doe'));
      });

      test('should access array elements by index', () {
        final json = Json({
          'users': [
            {'name': 'Alice', 'age': 25},
            {'name': 'Bob', 'age': 30},
            {'name': 'Charlie', 'age': 35},
          ]
        });

        expect(json.path<String>('users.0.name'), equals('Alice'));
        expect(json.path<int>('users.0.age'), equals(25));
        expect(json.path<String>('users.1.name'), equals('Bob'));
        expect(json.path<int>('users.2.age'), equals(35));
      });

      test('should handle nested arrays', () {
        final json = Json({
          'matrix': [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ]
        });

        expect(json.path<int>('matrix.0.0'), equals(1));
        expect(json.path<int>('matrix.1.1'), equals(5));
        expect(json.path<int>('matrix.2.2'), equals(9));
      });

      test('should handle complex mixed structures', () {
        final json = Json({
          'company': {
            'name': 'TechCorp',
            'departments': [
              {
                'name': 'Engineering',
                'employees': [
                  {'name': 'Alice', 'role': 'Developer'},
                  {'name': 'Bob', 'role': 'Manager'},
                ]
              },
              {
                'name': 'Sales',
                'employees': [
                  {'name': 'Charlie', 'role': 'Sales Rep'},
                ]
              },
            ]
          }
        });

        expect(json.path<String>('company.name'), equals('TechCorp'));
        expect(json.path<String>('company.departments.0.name'), equals('Engineering'));
        expect(json.path<String>('company.departments.0.employees.0.name'), equals('Alice'));
        expect(json.path<String>('company.departments.0.employees.1.role'), equals('Manager'));
        expect(json.path<String>('company.departments.1.employees.0.name'), equals('Charlie'));
      });

      test('should use custom separator', () {
        final json = Json({
          'user': {
            'profile': {
              'name': 'Alice',
            }
          }
        });

        expect(json.path<String>('user/profile/name', separator: '/'), equals('Alice'));
        expect(json.path<String>('user->profile->name', separator: '->'), equals('Alice'));
      });

      test('should throw ArgumentError for invalid path', () {
        final json = Json({
          'user': {'name': 'Alice'}
        });

        expect(
          () => json.path<String>('user.missing.field'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Path traversal failed'),
          )),
        );
      });

      test('should throw ArgumentError for invalid array index', () {
        final json = Json({
          'users': [
            {'name': 'Alice'},
          ]
        });

        expect(
          () => json.path<String>('users.5.name'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid array index'),
          )),
        );

        expect(
          () => json.path<String>('users.-1.name'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid array index'),
          )),
        );
      });

      test('should throw ArgumentError for invalid type', () {
        final json = Json({
          'user': {'name': 'Alice'}
        });

        expect(
          () => json.path<int>('user.name'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid type'),
          )),
        );
      });

      test('should use fallback for missing path', () {
        final json = Json({
          'user': {'name': 'Alice'}
        });

        expect(
          json.path<String>('user.missing', fallback: () => 'default'),
          equals('default'),
        );
      });

      test('should use fallback for invalid array index', () {
        final json = Json({
          'users': [
            {'name': 'Alice'},
          ]
        });

        expect(
          json.path<String>('users.10.name', fallback: () => 'unknown'),
          equals('unknown'),
        );
      });

      test('should use fallback for invalid type', () {
        final json = Json({
          'user': {'age': '25'}
        });

        expect(
          json.path<int>('user.age', fallback: () => 0),
          equals(0),
        );
      });

      test('should handle null values in path', () {
        final json = Json({
          'user': null,
        });

        expect(
          () => json.path<String>('user.name'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('value is null'),
          )),
        );

        expect(
          json.path<String>('user.name', fallback: () => 'default'),
          equals('default'),
        );
      });

      test('should handle primitive values in middle of path', () {
        final json = Json({
          'user': 'Alice',
        });

        expect(
          () => json.path<String>('user.name'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('expected Map or List'),
          )),
        );
      });

      test('should support nullable types', () {
        final json = Json({
          'user': {
            'name': 'Alice',
            'email': null,
          }
        });

        expect(json.path<String>('user.name'), equals('Alice'));
        expect(json.path<String?>('user.email'), isNull);
      });

      test('should handle bracket notation for arrays', () {
        final json = Json({
          'users': [
            {'name': 'Alice'},
            {'name': 'Bob'},
          ]
        });

        expect(json.path<String>('users[0].name'), equals('Alice'));
        expect(json.path<String>('users[1].name'), equals('Bob'));
      });

      test('should handle nested bracket notation', () {
        final json = Json({
          'data': {
            'items': [
              {
                'tags': ['red', 'blue', 'green']
              },
              {
                'tags': ['yellow', 'purple']
              }
            ]
          }
        });

        expect(json.path<String>('data.items[0].tags[0]'), equals('red'));
        expect(json.path<String>('data.items[0].tags[2]'), equals('green'));
        expect(json.path<String>('data.items[1].tags[1]'), equals('purple'));
      });

      test('should handle complex bracket notation', () {
        final json = Json({
          'users': [
            {
              'name': 'Alice',
              'friends': [
                {'name': 'Bob'},
                {'name': 'Charlie'},
              ]
            }
          ]
        });

        expect(
          json.path<String>('users[0].friends[0].name'),
          equals('Bob'),
        );
        expect(
          json.path<String>('users[0].friends[1].name'),
          equals('Charlie'),
        );
      });

      test('should mix dot and bracket notation freely', () {
        final json = Json({
          'company': {
            'departments': [
              {
                'employees': [
                  {'name': 'Alice', 'skills': ['Dart', 'Flutter']},
                ]
              }
            ]
          }
        });

        expect(
          json.path<String>('company.departments[0].employees[0].name'),
          equals('Alice'),
        );
        expect(
          json.path<String>('company.departments[0].employees[0].skills[1]'),
          equals('Flutter'),
        );
      });

      test('should handle both notations for same data', () {
        final json = Json({
          'users': [
            {'name': 'Alice', 'age': 25},
          ]
        });

        // Both should return the same value
        expect(json.path<String>('users.0.name'), equals('Alice'));
        expect(json.path<String>('users[0].name'), equals('Alice'));
        expect(json.path<int>('users.0.age'), equals(25));
        expect(json.path<int>('users[0].age'), equals(25));
      });

      test('should use fallback with bracket notation', () {
        final json = Json({
          'users': [
            {'name': 'Alice'},
          ]
        });

        expect(
          json.path<String>('users[5].name', fallback: () => 'unknown'),
          equals('unknown'),
        );
      });
    });
  });
}

// Test helper classes
class User {
  final int id;
  final String name;

  User(this.id, this.name);
}

class Address {
  final String street;
  final int number;

  Address(this.street, this.number);
}

class DataWrapper {
  final User user;

  DataWrapper(this.user);
}

class Team {
  final String name;
  final List<User> members;

  Team(this.name, this.members);
}
