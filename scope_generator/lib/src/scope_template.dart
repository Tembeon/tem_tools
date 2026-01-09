/// Generates the IScopeController interface code.
///
/// This goes into `*_scope_controller.dart` file.
String generateScopeControllerCode({
  required String scopeName,
  required String controllerName,
}) {
  final stateName = '_${scopeName}State';
  final scopeControllerName = 'I${scopeName}Controller';

  final buffer = StringBuffer();

  buffer.writeln('/// Interface for scope-level actions in [$scopeName].');
  buffer.writeln('///');
  buffer.writeln('/// Implemented by [$stateName], accessed via');
  buffer.writeln('/// [$scopeName.scopeControllerOf].');
  buffer.writeln('abstract interface class $scopeControllerName {');
  buffer.write('}');

  return buffer.toString();
}

/// Generates Scope boilerplate code for a controller class.
///
/// The generated code follows the InheritedModel pattern with aspects:
/// - `XxxScope` - StatefulWidget wrapper with static accessors
/// - `_XxxScopeState` - State implementing `IXxxScopeController`
/// - `_XxxInherited` - InheritedModel with aspects for selective rebuilds
/// - `_XxxAspect` - Enum of subscribable aspects
///
/// This goes into `*_scope.dart` file.
String generateScopeCode({
  required String scopeName,
  required String controllerName,
  required String? stateType,
  required String controllerImportPath,
  required String scopeControllerImportPath,
}) {
  // Derive names
  final baseName = scopeName.replaceAll('Scope', '');
  final inheritedName = '_${baseName}Inherited';
  final stateName = '_${scopeName}State';
  final aspectName = '_${baseName}Aspect';
  final scopeControllerName = 'I${scopeName}Controller';
  final hasState = stateType != null && stateType != 'dynamic';

  // State field name in inherited (camelCase)
  final stateFieldName = '${_toCamelCase(baseName)}State';
  final scopeControllerFieldName = '${_toCamelCase(baseName)}ScopeController';
  final stateControllerFieldName = '${_toCamelCase(baseName)}StateController';

  final buffer = StringBuffer();

  // Imports
  buffer.writeln("import 'package:flutter/foundation.dart';");
  buffer.writeln("import 'package:flutter/material.dart';");
  buffer.writeln();
  buffer.writeln("import '$controllerImportPath';");
  buffer.writeln("import '$scopeControllerImportPath';");
  buffer.writeln();

  // ==================== Main Scope Widget ====================
  buffer.writeln('/// {@template $scopeName}');
  buffer.writeln('/// Scope for [$controllerName].');
  buffer.writeln('///');
  buffer.writeln('/// Provides access to state and controllers via static methods:');
  if (hasState) {
    buffer.writeln('/// - [stateOf] — returns current state (rebuilds on change)');
  }
  buffer.writeln('/// - [stateControllerOf] — returns state controller');
  buffer.writeln('/// - [scopeControllerOf] — returns scope controller for actions');
  buffer.writeln('/// {@endtemplate}');
  buffer.writeln('class $scopeName extends StatefulWidget {');
  buffer.writeln('  /// {@macro $scopeName}');
  buffer.writeln('  const $scopeName({required this.child, super.key});');
  buffer.writeln();
  buffer.writeln('  /// Child widget.');
  buffer.writeln('  final Widget child;');
  buffer.writeln();

  // stateOf method
  if (hasState) {
    buffer.writeln('  /// Returns current state from the nearest [$scopeName].');
    buffer.writeln('  /// Subscribes to state changes by default.');
    buffer.writeln('  static $stateType stateOf(BuildContext context, {bool listen = true}) =>');
    buffer.writeln('      $inheritedName.of(context, aspect: $aspectName.$stateFieldName, listen: listen).$stateFieldName;');
    buffer.writeln();
  }

  // stateControllerOf method
  buffer.writeln('  /// Returns state controller from the nearest [$scopeName].');
  buffer.writeln('  /// Does not subscribe to changes by default.');
  buffer.writeln('  static $controllerName stateControllerOf(BuildContext context, {bool listen = false}) =>');
  buffer.writeln('      $inheritedName.of(context, aspect: $aspectName.stateController, listen: listen).$stateControllerFieldName;');
  buffer.writeln();

  // scopeControllerOf method
  buffer.writeln('  /// Returns scope controller from the nearest [$scopeName].');
  buffer.writeln('  /// Does not subscribe to changes by default.');
  buffer.writeln('  static $scopeControllerName scopeControllerOf(BuildContext context, {bool listen = false}) =>');
  buffer.writeln('      $inheritedName.of(context, aspect: $aspectName.scopeController, listen: listen).$scopeControllerFieldName;');
  buffer.writeln();

  buffer.writeln('  @override');
  buffer.writeln('  State<$scopeName> createState() => $stateName();');
  buffer.writeln('}');
  buffer.writeln();

  // ==================== State Class ====================
  buffer.writeln('class $stateName extends State<$scopeName> implements $scopeControllerName {');
  buffer.writeln('  late final $controllerName _stateController;');
  buffer.writeln();
  buffer.writeln('  @override');
  buffer.writeln('  void initState() {');
  buffer.writeln('    super.initState();');
  buffer.writeln('    _stateController = $controllerName();');
  buffer.writeln('  }');
  buffer.writeln();
  buffer.writeln('  @override');
  buffer.writeln('  void dispose() {');
  buffer.writeln('    _stateController.dispose();');
  buffer.writeln('    super.dispose();');
  buffer.writeln('  }');
  buffer.writeln();
  buffer.writeln('  @override');
  buffer.writeln('  Widget build(BuildContext context) {');
  buffer.writeln('    return ListenableBuilder(');
  buffer.writeln('      listenable: _stateController,');
  buffer.writeln('      builder: (context, child) => $inheritedName(');
  if (hasState) {
    buffer.writeln('        $stateFieldName: _stateController.value,');
  }
  buffer.writeln('        $scopeControllerFieldName: this,');
  buffer.writeln('        $stateControllerFieldName: _stateController,');
  buffer.writeln('        child: child!,');
  buffer.writeln('      ),');
  buffer.writeln('      child: widget.child,');
  buffer.writeln('    );');
  buffer.writeln('  }');
  buffer.writeln('}');
  buffer.writeln();

  // ==================== Aspect Enum ====================
  buffer.writeln('/// Aspects for selective rebuilds in [$scopeName].');
  buffer.writeln('///');
  buffer.writeln('/// See: [InheritedModel].');
  buffer.writeln('enum $aspectName {');
  if (hasState) {
    buffer.writeln('  /// Subscribe to state changes.');
    buffer.writeln('  $stateFieldName,');
  }
  buffer.writeln('  /// Subscribe to scope controller changes.');
  buffer.writeln('  scopeController,');
  buffer.writeln('  /// Subscribe to state controller changes.');
  buffer.writeln('  stateController,');
  buffer.writeln('}');
  buffer.writeln();

  // ==================== InheritedModel ====================
  buffer.writeln('class $inheritedName extends InheritedModel<$aspectName> {');
  buffer.writeln('  const $inheritedName({');
  buffer.writeln('    required super.child,');
  if (hasState) {
    buffer.writeln('    required this.$stateFieldName,');
  }
  buffer.writeln('    required this.$scopeControllerFieldName,');
  buffer.writeln('    required this.$stateControllerFieldName,');
  buffer.writeln('  });');
  buffer.writeln();
  if (hasState) {
    buffer.writeln('  final $stateType $stateFieldName;');
  }
  buffer.writeln('  final $scopeControllerName $scopeControllerFieldName;');
  buffer.writeln('  final $controllerName $stateControllerFieldName;');
  buffer.writeln();

  // of method with FlutterError
  buffer.writeln('  static $inheritedName of(');
  buffer.writeln('    BuildContext context, {');
  buffer.writeln('    $aspectName? aspect,');
  buffer.writeln('    bool listen = true,');
  buffer.writeln('  }) {');
  buffer.writeln('    final result = listen');
  buffer.writeln('        ? context.dependOnInheritedWidgetOfExactType<$inheritedName>(aspect: aspect)');
  buffer.writeln('        : context.getInheritedWidgetOfExactType<$inheritedName>();');
  buffer.writeln();
  buffer.writeln('    if (result == null) {');
  buffer.writeln('      throw FlutterError.fromParts(<DiagnosticsNode>[');
  buffer.writeln("        ErrorSummary('No $scopeName widget ancestor found.'),");
  buffer.writeln('        ErrorDescription(');
  buffer.writeln("          '\${context.widget.runtimeType} widgets require a $scopeName widget ancestor.',");
  buffer.writeln('        ),');
  buffer.writeln("        context.describeWidget('The specific widget that could not find a $scopeName ancestor was'),");
  buffer.writeln("        context.describeOwnershipChain('The ownership chain for the affected widget is'),");
  buffer.writeln('      ]);');
  buffer.writeln('    }');
  buffer.writeln('    return result;');
  buffer.writeln('  }');
  buffer.writeln();

  // debugFillProperties
  buffer.writeln('  @override');
  buffer.writeln('  void debugFillProperties(DiagnosticPropertiesBuilder properties) {');
  buffer.writeln('    super.debugFillProperties(');
  buffer.writeln('      properties');
  if (hasState) {
    buffer.writeln("        ..add(DiagnosticsProperty<$stateType>('$stateFieldName', $stateFieldName))");
  }
  buffer.writeln("        ..add(DiagnosticsProperty<$scopeControllerName>('$scopeControllerFieldName', $scopeControllerFieldName))");
  buffer.writeln("        ..add(DiagnosticsProperty<$controllerName>('$stateControllerFieldName', $stateControllerFieldName)),");
  buffer.writeln('    );');
  buffer.writeln('  }');
  buffer.writeln();

  // updateShouldNotify
  buffer.writeln('  @override');
  buffer.writeln('  bool updateShouldNotify($inheritedName old) =>');
  final notifyChecks = <String>[];
  if (hasState) {
    notifyChecks.add('$stateFieldName != old.$stateFieldName');
  }
  notifyChecks.add('$scopeControllerFieldName != old.$scopeControllerFieldName');
  notifyChecks.add('$stateControllerFieldName != old.$stateControllerFieldName');
  buffer.writeln('      ${notifyChecks.join(' ||\n      ')};');
  buffer.writeln();

  // updateShouldNotifyDependent
  buffer.writeln('  @override');
  buffer.writeln('  bool updateShouldNotifyDependent(');
  buffer.writeln('    covariant $inheritedName oldWidget,');
  buffer.writeln('    Set<$aspectName> dependencies,');
  buffer.writeln('  ) {');
  buffer.writeln('    return dependencies.any(');
  buffer.writeln('      (aspect) => switch (aspect) {');
  if (hasState) {
    buffer.writeln('        $aspectName.$stateFieldName => oldWidget.$stateFieldName != $stateFieldName,');
  }
  buffer.writeln('        $aspectName.scopeController => oldWidget.$scopeControllerFieldName != $scopeControllerFieldName,');
  buffer.writeln('        $aspectName.stateController => oldWidget.$stateControllerFieldName != $stateControllerFieldName,');
  buffer.writeln('      },');
  buffer.writeln('    );');
  buffer.writeln('  }');
  buffer.write('}');

  return buffer.toString();
}

/// Converts PascalCase to camelCase.
String _toCamelCase(String name) {
  if (name.isEmpty) return name;
  return name[0].toLowerCase() + name.substring(1);
}
