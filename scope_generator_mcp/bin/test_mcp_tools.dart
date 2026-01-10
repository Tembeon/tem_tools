#!/usr/bin/env dart
// Tests the MCP server tools by calling them directly.
// Usage: dart run bin/test_mcp_tools.dart <workspace>
//
// Example:
//   dart run bin/test_mcp_tools.dart /path/to/scope_generator/example

import 'dart:io';

import 'package:scope_generator_mcp/src/lsp_client.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/test_mcp_tools.dart <workspace>');
    print('');
    print('Example:');
    print('  dart run bin/test_mcp_tools.dart \\');
    print('    /Volumes/T7/IdeaProjects/tem_tools/scope_generator/example');
    exit(1);
  }

  final workspace = args[0];
  final testFile =
      '$workspace/lib/example/controllers/example_state_controller.dart';

  // SimpleController is on line 5 (0-based: 4), class name starts at char 6
  const line = 4;
  const character = 6;

  print('=== Testing scope_generator_mcp LSP Client ===');
  print('Workspace: $workspace');
  print('Test file: $testFile');
  print('Position: line $line, char $character');
  print('');

  final lsp = DartLspClient();

  print('Initializing LSP...');
  await lsp.initialize(workspace);
  print('LSP initialized.');

  print('');
  print('Getting code actions (with warmup)...');
  final actions = await lsp.getCodeActions(testFile, line, character);

  print('Found ${actions.length} actions:');
  for (final action in actions) {
    print('  [${action['index']}] ${action['title']} (${action['kind']})');
  }

  // Check for our plugin action
  final generateScopeAction =
      actions.where((a) => a['title'] == 'Generate Scope wrapper').firstOrNull;

  print('');
  if (generateScopeAction == null) {
    print('✗ FAILED: "Generate Scope wrapper" action NOT found.');
    print('');
    print('Available actions:');
    for (final a in actions) {
      print('  - ${a['title']}');
    }
    await lsp.dispose();
    exit(1);
  }

  print('✓ SUCCESS: "Generate Scope wrapper" action is available!');
  print('');

  // Test applying the action
  print('Getting full action details...');
  final actionIndex = generateScopeAction['index'] as int;
  final fullAction = await lsp.getFullCodeAction(testFile, line, character, actionIndex);

  if (fullAction == null) {
    print('✗ FAILED: Could not get full action details');
    await lsp.dispose();
    exit(1);
  }

  print('✓ Got full action');
  final edit = fullAction['edit'] as Map<String, dynamic>?;

  if (edit == null) {
    print('✗ FAILED: Action has no edit');
    await lsp.dispose();
    exit(1);
  }

  print('✓ Action has edit');

  // Show what files would be created/modified
  final documentChanges = edit['documentChanges'] as List?;
  final changes = edit['changes'] as Map<String, dynamic>?;

  print('');
  if (documentChanges != null) {
    print('Document changes (${documentChanges.length}):');
    for (final change in documentChanges) {
      final kind = change['kind'] as String?;
      if (kind == 'create') {
        print('  CREATE: ${Uri.parse(change['uri'] as String).toFilePath()}');
      } else if (kind == 'delete') {
        print('  DELETE: ${Uri.parse(change['uri'] as String).toFilePath()}');
      } else {
        final textDoc = change['textDocument'] as Map<String, dynamic>?;
        if (textDoc != null) {
          final edits = (change['edits'] as List?)?.length ?? 0;
          print('  MODIFY: ${Uri.parse(textDoc['uri'] as String).toFilePath()} ($edits edits)');
        }
      }
    }
  } else if (changes != null) {
    print('Changes (${changes.length} files):');
    for (final entry in changes.entries) {
      final uri = Uri.parse(entry.key);
      final edits = (entry.value as List).length;
      print('  ${uri.toFilePath()} ($edits edits)');
    }
  } else {
    print('Edit structure:');
    print('  Keys: ${edit.keys.toList()}');
  }

  print('');
  print('✓ All tests passed! (Action not applied to avoid modifying files)');

  await lsp.dispose();
  print('');
  print('Done.');
}
