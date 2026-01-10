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
///
/// Generates two files:
/// - `*_scope.dart` - Scope widget, InheritedModel, aspects enum
/// - `*_scope_controller.dart` - IScopeController interface
class GenerateScopeAssist extends ResolvedCorrectionProducer {
  static const _assistKind = AssistKind(
    'dart.assist.scope_generator.generateScope',
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

    // Derive file paths
    final currentFilePath = file;
    final directory = _getDirectory(currentFilePath);

    // Derive new file names based on scope name
    final scopeBaseName = _toSnakeCase(scopeName);
    final scopeFilePath = '$directory/$scopeBaseName.dart';
    final scopeControllerFilePath = '$directory/${scopeBaseName}_controller.dart';

    // Get package name and convert to package: imports
    final packageName = _getPackageName(currentFilePath);
    final libRelativePath = _getLibRelativePath(currentFilePath);
    final libRelativeDir = _getDirectory(libRelativePath);

    // Import paths (package:)
    final controllerImportPath = 'package:$packageName/$libRelativePath';
    final scopeControllerImportPath = 'package:$packageName/$libRelativeDir/${scopeBaseName}_controller.dart';

    // Generate code for scope controller interface
    final scopeControllerCode = generateScopeControllerCode(
      scopeName: scopeName,
      controllerName: controllerName,
    );

    // Generate code for scope
    final scopeCode = generateScopeCode(
      scopeName: scopeName,
      controllerName: controllerName,
      stateType: stateType,
      controllerImportPath: controllerImportPath,
      scopeControllerImportPath: scopeControllerImportPath,
    );

    // Create scope controller file
    await builder.addDartFileEdit(scopeControllerFilePath, (builder) {
      builder.addInsertion(0, (builder) {
        builder.write(scopeControllerCode);
      });
    });

    // Create scope file
    await builder.addDartFileEdit(scopeFilePath, (builder) {
      builder.addInsertion(0, (builder) {
        builder.write(scopeCode);
      });
    });
  }

  /// Gets the directory part of a file path.
  String _getDirectory(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return '.';
    return filePath.substring(0, lastSlash);
  }

  /// Gets the file name from a file path.
  String _getFileName(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return filePath;
    return filePath.substring(lastSlash + 1);
  }

  /// Extracts package name from file path.
  ///
  /// Looks for the directory name right before 'lib/' in the path.
  /// E.g., `/path/to/my_app/lib/src/file.dart` → `my_app`
  String _getPackageName(String filePath) {
    final parts = filePath.split('/');
    final libIndex = parts.indexOf('lib');
    if (libIndex > 0) {
      return parts[libIndex - 1];
    }
    // Fallback: use parent directory name
    return parts[parts.length - 2];
  }

  /// Gets path relative to lib/ directory.
  ///
  /// E.g., `/path/to/my_app/lib/features/auth/auth_controller.dart`
  /// → `features/auth/auth_controller.dart`
  String _getLibRelativePath(String filePath) {
    final libIndex = filePath.indexOf('/lib/');
    if (libIndex != -1) {
      return filePath.substring(libIndex + 5); // +5 to skip '/lib/'
    }
    // Fallback: return file name
    return _getFileName(filePath);
  }

  /// Converts PascalCase to snake_case.
  String _toSnakeCase(String name) {
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (char.toUpperCase() == char && char.toLowerCase() != char) {
        if (i > 0) buffer.write('_');
        buffer.write(char.toLowerCase());
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
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
