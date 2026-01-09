import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:scope_generator/src/scope_template.dart';

/// Quick assist that generates a Scope wrapper for Listenable-based controllers.
///
/// Activated when cursor is on a class declaration that extends:
/// - `Listenable`
/// - `ChangeNotifier`
/// - `ValueNotifier<T>`
/// - Or any subclass of the above
class GenerateScopeAssist extends ResolvedCorrectionProducer {
  static const _assistKind = AssistKind(
    'scope_generator.generateScope',
    30,
    'Generate Scope wrapper',
  );

  GenerateScopeAssist({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => _assistKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // Find the class declaration at cursor
    final classDecl = node.thisOrAncestorOfType<ClassDeclaration>();
    if (classDecl == null) return;

    // Check if extends Listenable
    final extendsClause = classDecl.extendsClause;
    if (extendsClause == null) return;

    final superclassType = extendsClause.superclass.type;
    if (superclassType == null) return;

    if (!_isListenableType(superclassType)) return;

    // Extract names
    final controllerName = classDecl.name.lexeme;
    final scopeName = _deriveScopeName(controllerName);
    final stateType = _extractStateType(superclassType);

    // Generate code
    final scopeCode = generateScopeCode(
      scopeName: scopeName,
      controllerName: controllerName,
      stateType: stateType,
    );

    await builder.addDartFileEdit(file, (builder) {
      // Insert after the class declaration
      builder.addInsertion(classDecl.end, (builder) {
        builder.write('\n\n');
        builder.write(scopeCode);
      });
    });
  }

  /// Checks if the type is or extends Listenable.
  bool _isListenableType(DartType type) {
    if (type is! InterfaceType) return false;

    final element = type.element;

    // Check if this type or any supertype is Listenable
    return _implementsListenable(element);
  }

  /// Recursively checks if element implements Listenable.
  bool _implementsListenable(InterfaceElement element) {
    final name = element.name;

    // Direct match
    if (name == 'Listenable' ||
        name == 'ChangeNotifier' ||
        name == 'ValueNotifier' ||
        name == 'ValueListenable') {
      return true;
    }

    // Check superclass
    if (element is ClassElement) {
      final supertype = element.supertype;
      if (supertype != null && _implementsListenable(supertype.element)) {
        return true;
      }
    }

    // Check interfaces
    for (final interface in element.interfaces) {
      if (_implementsListenable(interface.element)) {
        return true;
      }
    }

    // Check mixins
    if (element is ClassElement) {
      for (final mixin in element.mixins) {
        if (_implementsListenable(mixin.element)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Derives scope name from controller name.
  ///
  /// Examples:
  /// - `JamsStateController` → `JamsScope`
  /// - `AuthController` → `AuthScope`
  /// - `UserNotifier` → `UserScope`
  String _deriveScopeName(String controllerName) {
    var name = controllerName;

    // Remove common suffixes
    const suffixes = [
      'StateController',
      'Controller',
      'Notifier',
      'Listenable',
    ];

    for (final suffix in suffixes) {
      if (name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length);
        break;
      }
    }

    // If nothing removed, just use the name
    if (name.isEmpty) {
      name = controllerName;
    }

    return '${name}Scope';
  }

  /// Extracts state type from `ValueNotifier<T>` or similar.
  ///
  /// Returns `null` if no type parameter found (e.g., plain `ChangeNotifier`).
  String? _extractStateType(DartType type) {
    if (type is! InterfaceType) return null;

    // Check if it's ValueNotifier<T> or similar with type argument
    final typeArgs = type.typeArguments;
    if (typeArgs.isNotEmpty) {
      final stateType = typeArgs.first;
      // Get the display string without nullability suffix for cleaner output
      return stateType.getDisplayString();
    }

    // Check superclass for type argument
    final element = type.element;
    if (element is ClassElement) {
      final supertype = element.supertype;
      if (supertype != null) {
        return _extractStateType(supertype);
      }
    }

    return null;
  }
}
