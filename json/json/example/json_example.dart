import 'package:json/json.dart';
import 'dart:convert';

const jsonString = '''
{
  "name": "John",
  "age": 30,
  "city": "New York",
  "isActive": true,
  "salary": 75000.50,
  "address": {
    "street": "123 Main St",
    "city": "New York",
    "state": "NY",
    "zip": "10001",
    "country": "USA"
  },
  "tags": ["developer", "programmer", "engineer"],
  "projects": [
    {
      "id": 1,
      "name": "Project A",
      "status": "active"
    },
    {
      "id": 2,
      "name": "Project B",
      "status": "completed"
    }
  ],
  "skills": {
    "languages": ["Dart", "Python", "JavaScript"],
    "frameworks": ["Flutter", "Django", "React"]
  }
}
''';

// Custom class for demonstration
class Address {
  final String street;
  final String city;
  final String state;
  final String zip;
  final String country;

  Address({
    required this.street,
    required this.city,
    required this.state,
    required this.zip,
    required this.country,
  });

  factory Address.fromJson(Json json) {
    return Address(
      street: json('street'),
      city: json('city'),
      state: json('state'),
      zip: json('zip'),
      country: json('country'),
    );
  }

  @override
  String toString() => '$street, $city, $state $zip, $country';
}

class Project {
  final int id;
  final String name;
  final String status;

  Project({
    required this.id,
    required this.name,
    required this.status,
  });

  factory Project.fromJson(Json json) {
    return Project(
      id: json('id'),
      name: json('name'),
      status: json('status'),
    );
  }

  @override
  String toString() => 'Project($id: $name - $status)';
}

void main() {
  final json = Json(jsonDecode(jsonString));

  print('=== Json Extension Type - All Features Demo ===\n');

  // 1. Using call() method - automatic type inference
  print('1. call() Method - Automatic Type Inference:');
  String name = json('name'); // Type inferred as String
  int age = json('age'); // Type inferred as int
  bool isActive = json('isActive'); // Type inferred as bool
  double salary = json('salary'); // Type inferred as double
  List<Object?> tags = json('tags'); // Type inferred as List

  print('   Name: $name');
  print('   Age: $age');
  print('   Active: $isActive');
  print('   Salary: \$$salary');
  print('   Tags: $tags\n');

  // 2. Using call() with fallback
  print('2. call() Method with Fallback:');
  String email = json('email', fallback: () => 'no-email@example.com');
  String phone = json('phone', fallback: () => 'N/A');
  print('   Email: $email');
  print('   Phone: $phone\n');

  // 3. Using parseJson() for nested objects
  print('3. parseJson() - Parse Nested Objects:');
  final address = json.parseJson<Address>('address', fromJson: Address.fromJson);
  print('   Address: $address\n');

  // 4. Using parseJsonList() for arrays of objects
  print('4. parseJsonList() - Parse Arrays of Objects:');
  final projects = json.parseJsonList<Project>(
    'projects',
    fromJson: (list) => list.map((j) => Project.fromJson(j)).toList(),
  );
  print('   Projects:');
  for (final project in projects) {
    print('     - $project');
  }
  print('');

  // 5. Using path() with dot notation
  print('5. path() Method - Dot Notation:');
  String street = json.path<String>('address.street');
  String zipCode = json.path<String>('address.zip');
  String firstTag = json.path<String>('tags.0');
  print('   Street: $street');
  print('   ZIP: $zipCode');
  print('   First Tag: $firstTag\n');

  // 6. Using path() with bracket notation
  print('6. path() Method - Bracket Notation:');
  String secondTag = json.path<String>('tags[1]');
  String thirdTag = json.path<String>('tags[2]');
  int projectId = json.path<int>('projects[0].id');
  String projectName = json.path<String>('projects[1].name');
  print('   Second Tag: $secondTag');
  print('   Third Tag: $thirdTag');
  print('   First Project ID: $projectId');
  print('   Second Project Name: $projectName\n');

  // 7. Using path() with nested arrays
  print('7. path() - Deeply Nested Paths:');
  String firstLanguage = json.path<String>('skills.languages[0]');
  String secondFramework = json.path<String>('skills.frameworks[1]');
  List<Object?> allLanguages = json.path<List<Object?>>('skills.languages');
  print('   First Language: $firstLanguage');
  print('   Second Framework: $secondFramework');
  print('   All Languages: $allLanguages\n');

  // 8. Using path() with fallback
  print('8. path() with Fallback:');
  String missingField = json.path<String>(
    'nonexistent.field',
    fallback: () => 'Default Value',
  );
  int missingAge = json.path<int>(
    'address.age',
    fallback: () => 0,
  );
  print('   Missing Field: $missingField');
  print('   Missing Age: $missingAge\n');

  // 9. Using path() with custom separator
  print('9. path() with Custom Separator:');
  String customPath = json.path<String>('address/city', separator: '/');
  String customNestedPath = json.path<String>('skills/frameworks[0]', separator: '/');
  print('   City (using /): $customPath');
  print('   First Framework (using /): $customNestedPath\n');

  // 10. parse() method with custom transformation
  print('10. parse() Method - Custom Type Transformation:');
  final cityUpper = json.parse<String, String>(
    'city',
    fromJson: (city) => city.toUpperCase(),
  );
  print('   City (uppercase): $cityUpper\n');

  // 11. Combining methods
  print('11. Combining Multiple Methods:');
  final addressJson = json.parseJson<Json>('address', fromJson: (j) => j);
  String addressCity = addressJson('city');
  String addressCountry = addressJson.path<String>('country');
  print('   City from nested Json: $addressCity');
  print('   Country via path: $addressCountry\n');

  // 12. Working with Map methods (since Json implements Map)
  print('12. Map Implementation:');
  print('   Keys: ${json.keys.take(5).toList()}...');
  print('   Contains "name": ${json.containsKey('name')}');
  print('   Contains "email": ${json.containsKey('email')}');
  print('   Total fields: ${json.length}\n');

  print('=== Demo Complete ===');
}
