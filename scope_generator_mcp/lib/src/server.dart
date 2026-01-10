import 'package:scope_generator_mcp/src/lsp_client.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Creates and configures the MCP server with scope_generator tools.
Future<McpServer> createServer(String workspaceRoot) async {
  final lsp = DartLspClient();

  final server = McpServer(
    Implementation(name: 'scope_generator_mcp', version: '1.0.0'),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );

  // Initialize LSP before registering tools
  await lsp.initialize(workspaceRoot);

  // Tool: generate_scope
  server.registerTool(
    'generate_scope',
    description: 'Generate Scope wrapper for a controller class. '
        'Creates two files: *_scope.dart (InheritedModel + Widget) and *_scope_controller.dart (interface). '
        'Supported base classes: Listenable, ChangeNotifier, ValueNotifier, StateController. '
        'Example: in user_controller.dart, place cursor on "class UserController extends StateController" → '
        'generates user_scope.dart and user_scope_controller.dart.',
    inputSchema: JsonObject(
      properties: {
        'file': JsonString(description: 'Absolute path to controller .dart file (e.g., user_controller.dart)'),
        'line': JsonInteger(description: 'Line of class declaration (0-based)'),
        'character': JsonInteger(description: 'Character position on the class name (0-based)'),
      },
      required: ['file', 'line', 'character'],
    ),
    callback: (args, extra) async {
      try {
        final file = args['file'] as String;
        final line = args['line'] as int;
        final character = args['character'] as int;

        final result = await _applyActionByTitle(
          lsp,
          file,
          line,
          character,
          'Generate Scope wrapper',
        );

        return result;
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Error: $e')],
        );
      }
    },
  );

  // Tool: add_scope_aspect
  server.registerTool(
    'add_scope_aspect',
    description: 'Expose an immutable State field as Scope aspect for fine-grained widget rebuilds. '
        'Use on fields inside state data classes (e.g., UserState, SettingsState), NOT controllers. '
        'Example: in user_state.dart on "final String? name;" → widgets can subscribe to name changes only. '
        'Adds: enum value in _XxxAspect, case in updateShouldNotifyDependent, accessor method in Scope.',
    inputSchema: JsonObject(
      properties: {
        'file': JsonString(description: 'Absolute path to state .dart file (e.g., user_state.dart)'),
        'line': JsonInteger(description: 'Line of field declaration (0-based)'),
        'character': JsonInteger(description: 'Character position on the field name (0-based)'),
      },
      required: ['file', 'line', 'character'],
    ),
    callback: (args, extra) async {
      try {
        final file = args['file'] as String;
        final line = args['line'] as int;
        final character = args['character'] as int;

        final result = await _applyActionByTitle(
          lsp,
          file,
          line,
          character,
          'Expose as Scope aspect',
        );

        return result;
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Error: $e')],
        );
      }
    },
  );

  return server;
}

/// Finds and applies a code action by its title.
Future<CallToolResult> _applyActionByTitle(
  DartLspClient lsp,
  String file,
  int line,
  int character,
  String targetTitle,
) async {
  final actions = await lsp.getCodeActions(file, line, character);

  // Find action by title
  final actionIndex = actions.indexWhere(
    (a) => a['title'] == targetTitle,
  );

  if (actionIndex == -1) {
    final available = actions.map((a) => a['title']).join(', ');
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text: 'Action "$targetTitle" not available at this position. '
              'Available: ${available.isEmpty ? "none" : available}',
        ),
      ],
    );
  }

  final action = await lsp.getFullCodeAction(file, line, character, actionIndex);

  if (action == null) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Failed to get action details')],
    );
  }

  final edit = action['edit'] as Map<String, dynamic>?;

  if (edit == null) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'Action has no edit')],
    );
  }

  await lsp.applyEdit(edit);

  return CallToolResult(
    content: [TextContent(text: 'Done: $targetTitle')],
  );
}
