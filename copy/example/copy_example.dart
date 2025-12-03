import 'package:copy/copy.dart';

void main() {
  final example = SomeObject(value: 'value', id: 1);
  print(example.copyWith()); // SomeObject{value: value, id: 1}
  print(example.copyWith(value: () => null)); // SomeObject{value: null, id: 1}
  print(example.copyWith(id: null)); // SomeObject{value: value, id: 1} <- there is diff between passing function resulting null or passing null
  print(example.copyWith(id: () => null)); // SomeObject{value: value, id: null}
}

final class SomeObject {
  const SomeObject({this.id, this.value});

  final int? id;
  final String? value;

  SomeObject copyWith({ValueGetter<int?>? id, ValueGetter<String?>? value}) =>
      SomeObject(id: id.or(this.id), value: value.or(this.value));
}
