import 'dart:io';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';

/// Quick assist that exposes a State class field as a Scope aspect.
///
/// Activated when cursor is on a field declaration inside a State-like class.
/// Finds the corresponding `*_scope.dart` file and adds:
/// - Enum value in `_XxxAspect`
/// - Case in `updateShouldNotifyDependent` (compares via existing state)
/// - Accessor method in Scope widget
///
/// Does NOT duplicate the field in InheritedModel - uses existing state object.
class AddAspectAssist extends ResolvedCorrectionProducer {
  static const _assistKind = AssistKind(
    'dart.assist.scope_generator.addAspect',
    30,
    'Expose as Scope aspect',
  );

  AddAspectAssist({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => _assistKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // Find field declaration at cursor
    final fieldDecl = node.thisOrAncestorOfType<FieldDeclaration>();
    if (fieldDecl == null) return;

    // Get the containing class
    final classDecl = fieldDecl.thisOrAncestorOfType<ClassDeclaration>();
    if (classDecl == null) return;

    // Check if this looks like a State class
    // Supports: sealed class, final class, or class ending with 'State'
    if (!_isStateClass(classDecl)) return;

    // Get field info
    final fields = fieldDecl.fields;
    if (fields.variables.isEmpty) return;

    final fieldVar = fields.variables.first;
    final fieldName = fieldVar.name.lexeme;
    final fieldType = fields.type?.toSource() ?? 'dynamic';

    // Find scope file path (searches in feature folder)
    final currentFilePath = file;
    final scopeFilePath = _findScopeFilePath(currentFilePath);

    // No scope file found
    if (scopeFilePath == null) return;

    // Read scope file content
    final content = File(scopeFilePath).readAsStringSync();
    final lines = content.split('\n');

    // Parse to find insertion points
    final parsed = _parseScopeFile(lines);
    if (parsed == null) return;

    // Check if aspect already exists
    if (parsed.existingAspects.contains(fieldName)) return;

    // Build new content
    final newLines = List<String>.from(lines);

    // 1. Add accessor in Scope widget (before @override createState)
    final accessorCode = [
      '',
      '  /// Returns $fieldName from the nearest [${parsed.scopeName}].',
      '  /// Subscribes to $fieldName changes only.',
      '  static $fieldType ${fieldName}Of(BuildContext context, {bool listen = true}) =>',
      '      ${parsed.inheritedName}.of(context, aspect: ${parsed.aspectEnumName}.$fieldName, listen: listen).${parsed.stateFieldName}.$fieldName;',
    ];
    _insertLines(newLines, parsed.createStateLineIndex, accessorCode);

    // Adjust indices after insertion
    final offset1 = accessorCode.length;

    // 2. Add enum value (after last existing aspect)
    final enumValueCode = [
      '',
      '  /// Subscribe to $fieldName changes.',
      '  $fieldName,',
    ];
    _insertLines(newLines, parsed.lastAspectLineIndex + offset1 + 1, enumValueCode);

    final offset2 = offset1 + enumValueCode.length;

    // 3. Add case in updateShouldNotifyDependent switch
    final caseCode = [
      '        ${parsed.aspectEnumName}.$fieldName => oldWidget.${parsed.stateFieldName}.$fieldName != ${parsed.stateFieldName}.$fieldName,',
    ];
    _insertLines(newLines, parsed.lastSwitchCaseLineIndex + offset2 + 1, caseCode);

    // Write the modified content
    final newContent = newLines.join('\n');

    await builder.addGenericFileEdit(scopeFilePath, (builder) {
      builder.addSimpleReplacement(
        SourceRange(0, content.length),
        newContent,
      );
    });
  }

  void _insertLines(List<String> lines, int index, List<String> newLines) {
    for (var i = newLines.length - 1; i >= 0; i--) {
      lines.insert(index, newLines[i]);
    }
  }

  /// Checks if the class looks like a State class.
  bool _isStateClass(ClassDeclaration classDecl) {
    final name = classDecl.name.lexeme;

    // Check naming convention first (most reliable)
    if (name.endsWith('State')) {
      return true;
    }

    // Check for sealed/final/base class modifiers (common for state classes)
    if (classDecl.sealedKeyword != null ||
        classDecl.finalKeyword != null ||
        classDecl.baseKeyword != null) {
      return true;
    }

    return false;
  }

  /// Finds scope file path by searching in feature folder.
  ///
  /// Searches for `*_scope.dart` matching the controller name
  /// within the feature root directory (e.g., `lib/features/example/`).
  String? _findScopeFilePath(String controllerFilePath) {
    final fileName = _getFileName(controllerFilePath);

    // Derive expected scope file name
    var baseName = fileName.replaceAll('.dart', '');
    if (baseName.endsWith('_state_controller')) {
      baseName = baseName.substring(0, baseName.length - '_state_controller'.length);
    } else if (baseName.endsWith('_controller')) {
      baseName = baseName.substring(0, baseName.length - '_controller'.length);
    }
    final scopeFileName = '${baseName}_scope.dart';

    // Find feature root (go up until we hit lib/features/xxx or lib/xxx)
    final featureRoot = _findFeatureRoot(controllerFilePath);
    if (featureRoot == null) return null;

    // Search recursively for scope file
    return _findFileRecursively(featureRoot, scopeFileName);
  }

  /// Finds the feature root directory.
  ///
  /// Walks up from the file path until finding a "feature-like" directory:
  /// - `lib/features/xxx/` → returns `lib/features/xxx`
  /// - `lib/xxx/` → returns `lib/xxx`
  /// - Falls back to immediate parent directory
  String? _findFeatureRoot(String filePath) {
    final parts = filePath.split('/');

    // Find 'lib' index
    final libIndex = parts.indexOf('lib');
    if (libIndex == -1) {
      // No lib folder, use parent directory
      return _getDirectory(filePath);
    }

    // Check for lib/features/xxx pattern
    if (libIndex + 2 < parts.length && parts[libIndex + 1] == 'features') {
      // Return lib/features/xxx
      return parts.sublist(0, libIndex + 3).join('/');
    }

    // Check for lib/xxx pattern (direct subfolder of lib)
    if (libIndex + 1 < parts.length) {
      // Return lib/xxx
      return parts.sublist(0, libIndex + 2).join('/');
    }

    // Fallback to parent directory
    return _getDirectory(filePath);
  }

  /// Recursively searches for a file in a directory.
  String? _findFileRecursively(String directory, String fileName) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return null;

    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('/$fileName')) {
          return entity.path;
        }
      }
    } catch (_) {
      // Permission errors, etc.
    }

    return null;
  }

  String _getDirectory(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return '.';
    return filePath.substring(0, lastSlash);
  }

  String _getFileName(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return filePath;
    return filePath.substring(lastSlash + 1);
  }

  /// Parses scope file to find line indices for insertions.
  _ParsedScopeFile? _parseScopeFile(List<String> lines) {
    String? scopeName;
    String? aspectEnumName;
    String? inheritedName;
    String? stateFieldName;
    int? createStateLineIndex;
    int? lastAspectLineIndex;
    int? lastSwitchCaseLineIndex;
    final existingAspects = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Find scope class name
      final scopeMatch = RegExp(r'class (\w+Scope) extends StatefulWidget').firstMatch(line);
      if (scopeMatch != null) {
        scopeName = scopeMatch.group(1);
      }

      // Find createState line (insertion point for accessor)
      if (line.contains('@override') && i + 1 < lines.length && lines[i + 1].contains('createState()')) {
        createStateLineIndex = i;
      }

      // Find aspect enum
      final enumMatch = RegExp(r'enum (_\w+Aspect) \{').firstMatch(line);
      if (enumMatch != null) {
        aspectEnumName = enumMatch.group(1);
      }

      // Find enum values (aspects)
      if (aspectEnumName != null && lastAspectLineIndex == null) {
        final aspectMatch = RegExp(r'^\s+(\w+),$').firstMatch(line);
        if (aspectMatch != null) {
          existingAspects.add(aspectMatch.group(1)!);
          lastAspectLineIndex = i;
        }
        // Check for enum closing
        if (line.trim() == '}' && existingAspects.isNotEmpty) {
          // lastAspectLineIndex stays at the last aspect
        }
      }

      // Find inherited class
      final inheritedMatch = RegExp(r'class (_\w+Inherited) extends InheritedModel').firstMatch(line);
      if (inheritedMatch != null) {
        inheritedName = inheritedMatch.group(1);
      }

      // Find state field name in inherited (e.g., "final ExampleState exampleState;")
      if (inheritedName != null && stateFieldName == null) {
        final stateFieldMatch = RegExp(r'final \w+State (\w+);').firstMatch(line);
        if (stateFieldMatch != null) {
          stateFieldName = stateFieldMatch.group(1);
        }
      }

      // Find last switch case in updateShouldNotifyDependent
      if (line.contains('=> oldWidget.') && line.contains('!=')) {
        lastSwitchCaseLineIndex = i;
      }
    }

    if (scopeName == null ||
        aspectEnumName == null ||
        inheritedName == null ||
        stateFieldName == null ||
        createStateLineIndex == null ||
        lastAspectLineIndex == null ||
        lastSwitchCaseLineIndex == null) {
      return null;
    }

    return _ParsedScopeFile(
      scopeName: scopeName,
      aspectEnumName: aspectEnumName,
      inheritedName: inheritedName,
      stateFieldName: stateFieldName,
      createStateLineIndex: createStateLineIndex,
      lastAspectLineIndex: lastAspectLineIndex,
      lastSwitchCaseLineIndex: lastSwitchCaseLineIndex,
      existingAspects: existingAspects,
    );
  }
}

class _ParsedScopeFile {
  final String scopeName;
  final String aspectEnumName;
  final String inheritedName;
  final String stateFieldName;
  final int createStateLineIndex;
  final int lastAspectLineIndex;
  final int lastSwitchCaseLineIndex;
  final List<String> existingAspects;

  _ParsedScopeFile({
    required this.scopeName,
    required this.aspectEnumName,
    required this.inheritedName,
    required this.stateFieldName,
    required this.createStateLineIndex,
    required this.lastAspectLineIndex,
    required this.lastSwitchCaseLineIndex,
    required this.existingAspects,
  });
}
