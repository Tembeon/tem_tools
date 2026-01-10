import 'dart:io';

import 'package:scope_generator_mcp/scope_generator_mcp.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: scope_generator_mcp <workspace_path>');
    stderr.writeln('Example: scope_generator_mcp /path/to/flutter/project');
    exit(1);
  }

  final workspacePath = args.first;

  if (!Directory(workspacePath).existsSync()) {
    stderr.writeln('Error: Directory not found: $workspacePath');
    exit(1);
  }

  try {
    final server = await createServer(workspacePath);
    await server.connect(StdioServerTransport());
  } catch (e, st) {
    stderr.writeln('Error starting server: $e');
    stderr.writeln(st);
    exit(1);
  }
}
