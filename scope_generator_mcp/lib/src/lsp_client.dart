import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LSP client for communicating with Dart Analysis Server.
///
/// Uses JSON-RPC 2.0 over stdio to send requests and receive responses.
class DartLspClient {
  Process? _process;
  int _messageId = 0;
  final _pending = <int, Completer<dynamic>>{};
  StreamSubscription<String>? _subscription;

  final _openDocuments = <String>{};

  /// Starts the Dart language server and initializes it.
  Future<void> initialize(String workspaceRoot) async {

    _process = await Process.start(
      'dart',
      [
        'language-server',
        '--protocol=lsp',
        '--client-id=scope_generator_mcp',
        '--client-version=1.0.0',
      ],
      workingDirectory: workspaceRoot,
    );

    // Parse LSP messages from stdout
    final buffer = StringBuffer();
    _subscription = _process!.stdout
        .transform(utf8.decoder)
        .listen((chunk) => _handleChunk(chunk, buffer));

    final rootUri = Uri.directory(workspaceRoot).toString();

    // Send initialize request
    final initResult = await _sendRequest('initialize', {
      'processId': pid,
      'rootUri': rootUri,
      'workspaceFolders': [
        {'uri': rootUri, 'name': workspaceRoot.split('/').last},
      ],
      'capabilities': {
        'textDocument': {
          'codeAction': {
            'codeActionLiteralSupport': {
              'codeActionKind': {
                'valueSet': [
                  'quickfix',
                  'refactor',
                  'refactor.extract',
                  'refactor.inline',
                  'refactor.rewrite',
                  'source',
                  'source.organizeImports',
                  'source.fixAll',
                  // Plugin assists use dart.assist.* format
                  'dart.assist',
                  'dart.assist.scope_generator.generateScope',
                  'dart.assist.scope_generator.addAspect',
                ],
              },
            },
            'resolveSupport': {
              'properties': ['edit'],
            },
          },
        },
        'workspace': {
          'applyEdit': true,
          'workspaceFolders': true,
          'configuration': true,
        },
      },
      'initializationOptions': {
        'onlyAnalyzeProjectsWithOpenFiles': false,
        'suggestFromUnimportedLibraries': true,
      },
    });

    // Send initialized notification
    _sendNotification('initialized', {});

    // Wait for analysis server to fully initialize and load plugins
    await Future<void>.delayed(const Duration(seconds: 5));

    return initResult;
  }

  /// Opens a document for analysis.
  Future<void> openDocument(String filePath) async {
    if (_openDocuments.contains(filePath)) return;

    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File not found: $filePath');
    }

    final content = await file.readAsString();
    _sendNotification('textDocument/didOpen', {
      'textDocument': {
        'uri': Uri.file(filePath).toString(),
        'languageId': 'dart',
        'version': 1,
        'text': content,
      },
    });

    _openDocuments.add(filePath);
  }

  /// Gets available code actions at the specified position.
  ///
  /// Returns a list of compact action descriptors: {index, title, kind}.
  ///
  /// Note: Plugin assists may require a warmup request to load properly.
  /// This method sends two requests internally to ensure plugins are loaded.
  Future<List<Map<String, dynamic>>> getCodeActions(
    String filePath,
    int line,
    int character,
  ) async {
    await openDocument(filePath);

    final requestParams = {
      'textDocument': {'uri': Uri.file(filePath).toString()},
      'range': {
        'start': {'line': line, 'character': character},
        'end': {'line': line, 'character': character},
      },
      'context': {'diagnostics': <Map<String, dynamic>>[]},
    };

    // First request warms up plugins (they may not return results yet)
    await _sendRequest('textDocument/codeAction', requestParams);

    // Give plugin time to initialize after warmup
    await Future<void>.delayed(const Duration(seconds: 2));

    // Second request gets full results including plugin assists
    final result = await _sendRequest('textDocument/codeAction', requestParams);

    if (result == null) return <Map<String, dynamic>>[];

    final actions = (result as List).cast<Map<String, dynamic>>();

    // Return compact descriptors only
    return <Map<String, dynamic>>[
      for (var i = 0; i < actions.length; i++)
        {
          'index': i,
          'title': actions[i]['title'] as String,
          'kind': actions[i]['kind'] as String? ?? 'unknown',
        },
    ];
  }

  /// Gets the full code action at the specified index.
  ///
  /// This refetches the actions and returns the complete action with edits.
  Future<Map<String, dynamic>?> getFullCodeAction(
    String filePath,
    int line,
    int character,
    int actionIndex,
  ) async {
    await openDocument(filePath);

    final requestParams = {
      'textDocument': {'uri': Uri.file(filePath).toString()},
      'range': {
        'start': {'line': line, 'character': character},
        'end': {'line': line, 'character': character},
      },
      'context': {'diagnostics': <Map<String, dynamic>>[]},
    };

    // First request warms up plugins
    await _sendRequest('textDocument/codeAction', requestParams);

    // Give plugin time to initialize after warmup
    await Future<void>.delayed(const Duration(seconds: 2));

    // Second request gets full results
    final result = await _sendRequest('textDocument/codeAction', requestParams);

    if (result == null) return null;

    final actions = (result as List).cast<Map<String, dynamic>>();
    if (actionIndex < 0 || actionIndex >= actions.length) return null;

    return actions[actionIndex];
  }

  /// Applies a workspace edit.
  Future<void> applyEdit(Map<String, dynamic> edit) async {
    final changes = edit['changes'] as Map<String, dynamic>?;
    final documentChanges = edit['documentChanges'] as List?;

    if (documentChanges != null) {
      for (final change in documentChanges) {
        if (change is Map<String, dynamic>) {
          await _applyDocumentChange(change);
        }
      }
    } else if (changes != null) {
      for (final entry in changes.entries) {
        final uri = Uri.parse(entry.key);
        final edits = (entry.value as List).cast<Map<String, dynamic>>();
        await _applyTextEdits(uri.toFilePath(), edits);
      }
    }
  }

  Future<void> _applyDocumentChange(Map<String, dynamic> change) async {
    final kind = change['kind'] as String?;

    if (kind == 'create') {
      final uri = Uri.parse(change['uri'] as String);
      final file = File(uri.toFilePath());
      await file.create(recursive: true);
      await file.writeAsString('');
    } else if (kind == 'delete') {
      final uri = Uri.parse(change['uri'] as String);
      final file = File(uri.toFilePath());
      if (await file.exists()) {
        await file.delete();
      }
    } else {
      // TextDocumentEdit
      final textDocument = change['textDocument'] as Map<String, dynamic>;
      final uri = Uri.parse(textDocument['uri'] as String);
      final edits = (change['edits'] as List).cast<Map<String, dynamic>>();
      await _applyTextEdits(uri.toFilePath(), edits);
    }
  }

  Future<void> _applyTextEdits(
    String filePath,
    List<Map<String, dynamic>> edits,
  ) async {
    final file = File(filePath);

    String content;
    if (await file.exists()) {
      content = await file.readAsString();
    } else {
      await file.create(recursive: true);
      content = '';
    }

    final lines = content.split('\n');

    // Sort edits in reverse order to apply from end to start
    final sortedEdits = List<Map<String, dynamic>>.from(edits)
      ..sort((a, b) {
        final rangeA = a['range'] as Map<String, dynamic>;
        final rangeB = b['range'] as Map<String, dynamic>;
        final startA = rangeA['start'] as Map<String, dynamic>;
        final startB = rangeB['start'] as Map<String, dynamic>;
        final lineCompare =
            (startB['line'] as int).compareTo(startA['line'] as int);
        if (lineCompare != 0) return lineCompare;
        return (startB['character'] as int).compareTo(startA['character'] as int);
      });

    for (final edit in sortedEdits) {
      final range = edit['range'] as Map<String, dynamic>;
      final start = range['start'] as Map<String, dynamic>;
      final end = range['end'] as Map<String, dynamic>;
      final newText = edit['newText'] as String;

      final startLine = start['line'] as int;
      final startChar = start['character'] as int;
      final endLine = end['line'] as int;
      final endChar = end['character'] as int;

      // Convert to flat offset
      var startOffset = 0;
      for (var i = 0; i < startLine && i < lines.length; i++) {
        startOffset += lines[i].length + 1;
      }
      if (startLine < lines.length) {
        startOffset += startChar.clamp(0, lines[startLine].length);
      }

      var endOffset = 0;
      for (var i = 0; i < endLine && i < lines.length; i++) {
        endOffset += lines[i].length + 1;
      }
      if (endLine < lines.length) {
        endOffset += endChar.clamp(0, lines[endLine].length);
      }

      content = content.substring(0, startOffset) +
          newText +
          content.substring(endOffset);
    }

    await file.writeAsString(content);

    // Notify server about document change
    _openDocuments.remove(filePath);
  }

  void _handleChunk(String chunk, StringBuffer buffer) {
    buffer.write(chunk);

    while (true) {
      final content = buffer.toString();

      // Find Content-Length header
      final headerEnd = content.indexOf('\r\n\r\n');
      if (headerEnd == -1) break;

      final header = content.substring(0, headerEnd);
      final lengthMatch = RegExp(r'Content-Length: (\d+)').firstMatch(header);
      if (lengthMatch == null) break;

      final length = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;

      String body;
      if (content.length < bodyStart + length) {
        // Workaround: Sometimes large responses are truncated by a few bytes
        // Try to parse if we're very close (within 10 bytes)
        final missing = bodyStart + length - content.length;
        if (missing <= 10) {
          body = content.substring(bodyStart);
          buffer.clear();
        } else {
          break;
        }
      } else {
        body = content.substring(bodyStart, bodyStart + length);
        buffer.clear();
        buffer.write(content.substring(bodyStart + length));
      }

      try {
        _handleMessage(jsonDecode(body) as Map<String, dynamic>);
      } catch (e) {
        // JSON parsing error - likely due to truncation, skip this message
      }
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message.containsKey('id') && message.containsKey('result')) {
      // Response to our request
      final id = message['id'] as int;
      final completer = _pending.remove(id);
      completer?.complete(message['result']);
    } else if (message.containsKey('id') && message.containsKey('error')) {
      // Error response
      final id = message['id'] as int;
      final completer = _pending.remove(id);
      final error = message['error'] as Map<String, dynamic>;
      completer?.completeError(Exception(error['message']));
    } else if (message.containsKey('id') && message.containsKey('method')) {
      // Request FROM server - must respond
      final id = message['id'];
      final method = message['method'] as String;
      _handleServerRequest(id, method, message['params']);
    }
    // Notifications (no id, has method) are ignored
  }

  void _handleServerRequest(dynamic id, String method, dynamic params) {
    dynamic result;

    switch (method) {
      case 'workspace/configuration':
        // Return Dart settings for each requested scope
        final items = (params['items'] as List?) ?? [];
        result = [
          for (final _ in items)
            <String, dynamic>{}, // Empty config, use defaults
        ];
        break;

      case 'client/registerCapability':
        // Accept capability registration
        result = null;
        break;

      case 'window/workDoneProgress/create':
        // Accept progress token creation
        result = null;
        break;

      default:
        // Unknown request - return null
        result = null;
    }

    _sendResponse(id, result);
  }

  void _sendResponse(dynamic id, dynamic result) {
    final message = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });

    final content = 'Content-Length: ${message.length}\r\n\r\n$message';
    _process?.stdin.write(content);
  }

  Future<dynamic> _sendRequest(String method, Map<String, dynamic> params) {
    final id = _messageId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final message = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    final content = 'Content-Length: ${message.length}\r\n\r\n$message';
    _process?.stdin.write(content);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Request timed out: $method');
      },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final message = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });

    final content = 'Content-Length: ${message.length}\r\n\r\n$message';
    _process?.stdin.write(content);
  }

  /// Disposes the LSP client and kills the language server process.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _process?.kill();
    _process = null;
    _openDocuments.clear();
    _pending.clear();
  }
}
