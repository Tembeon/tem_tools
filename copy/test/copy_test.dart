// ignore_for_file: prefer_function_declarations_over_variables

import 'package:copy/copy.dart';
import 'package:test/test.dart';

void main() {
  group('ValueGetterX extension tests', () {
    test('or() returns other when ValueGetter is null', () {
      ValueGetter<int>? nullGetter;
      expect(nullGetter.or(42), equals(42));
    });

    test('or() returns function result when ValueGetter is not null', () {
      ValueGetter<int>? getter = () => 100;
      expect(getter.or(42), equals(100));
    });

    test('or() works with String type', () {
      ValueGetter<String>? nullGetter;
      expect(nullGetter.or('default'), equals('default'));

      ValueGetter<String>? getter = () => 'custom';
      expect(getter.or('default'), equals('custom'));
    });

    test('or() works with nullable types', () {
      ValueGetter<int?>? nullGetter;
      expect(nullGetter.or(null), isNull);
      expect(nullGetter.or(42), equals(42));

      ValueGetter<int?>? getterReturningNull = () => null;
      expect(getterReturningNull.or(42), isNull);

      ValueGetter<int?>? getterReturningValue = () => 100;
      expect(getterReturningValue.or(42), equals(100));
    });

    test('or() works with custom objects', () {
      final defaultPerson = Person('John', 30);
      final customPerson = Person('Jane', 25);

      ValueGetter<Person>? nullGetter;
      expect(nullGetter.or(defaultPerson), equals(defaultPerson));

      ValueGetter<Person>? getter = () => customPerson;
      expect(getter.or(defaultPerson), equals(customPerson));
    });

    test('or() works in copyWith pattern', () {
      final state = TestState(value: 10, name: 'initial', data: null);

      // Test updating only value
      final updated1 = state.copyWith(value: () => 20);
      expect(updated1.value, equals(20));
      expect(updated1.name, equals('initial'));
      expect(updated1.data, isNull);

      // Test updating only name
      final updated2 = state.copyWith(name: () => 'updated');
      expect(updated2.value, equals(10));
      expect(updated2.name, equals('updated'));
      expect(updated2.data, isNull);

      // Test setting nullable field to null
      final stateWithData = TestState(value: 10, name: 'test', data: 'some data');
      final updated3 = stateWithData.copyWith(data: () => null);
      expect(updated3.data, isNull);

      // Test updating multiple fields
      final updated4 = state.copyWith(
        value: () => 30,
        name: () => 'new name',
        data: () => 'new data',
      );
      expect(updated4.value, equals(30));
      expect(updated4.name, equals('new name'));
      expect(updated4.data, equals('new data'));

      // Test with no parameters (returns same values)
      final updated5 = state.copyWith();
      expect(updated5.value, equals(10));
      expect(updated5.name, equals('initial'));
      expect(updated5.data, isNull);
    });

    test('or() evaluates function only once', () {
      var callCount = 0;
      ValueGetter<int>? getter = () {
        callCount++;
        return 42;
      };

      final result = getter.or(0);
      expect(result, equals(42));
      expect(callCount, equals(1));
    });

    test('or() does not evaluate function when null', () {
      var callCount = 0;
      ValueGetter<int>? nullGetter;

      final result = nullGetter.or(10);
      expect(result, equals(10));
      expect(callCount, equals(0));
    });
  });
}

class Person {
  final String name;
  final int age;

  Person(this.name, this.age);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Person &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          age == other.age;

  @override
  int get hashCode => name.hashCode ^ age.hashCode;
}

class TestState {
  final int value;
  final String name;
  final String? data;

  TestState({
    required this.value,
    required this.name,
    this.data,
  });

  TestState copyWith({
    ValueGetter<int>? value,
    ValueGetter<String>? name,
    ValueGetter<String?>? data,
  }) =>
      TestState(
        value: value.or(this.value),
        name: name.or(this.name),
        data: data.or(this.data),
      );
}
