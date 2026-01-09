import 'package:control/control.dart';

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
