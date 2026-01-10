import 'package:control/control.dart';
import 'package:flutter/foundation.dart';

/// Test class that directly extends ChangeNotifier
class SimpleController extends ChangeNotifier {
  int _value = 0;
  int get value => _value;
  void increment() {
    _value++;
    notifyListeners();
  }
}

enum StateType { idle, loading, error }

/// Example state for the controller.
final class ExampleState {
  const ExampleState({this.stateType = StateType.idle, this.data, this.object});

  final StateType stateType;

  final String? data;

  final Object? object;
}

/// Example controller to test scope_generator plugin.
base class ExampleStateController extends StateController<ExampleState>
    with ConcurrentControllerHandler {
  ExampleStateController({super.initialState = const ExampleState()});
}
