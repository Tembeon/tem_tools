#!/usr/bin/env dart
// Simple test script to check if code actions work.
// Usage: dart run bin/test_actions.dart <workspace> <file> <line> [character]

import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart run bin/test_actions.dart <workspace> <file> <line> [character]');
    print('');
    print('Example:');
    print('  dart run bin/test_actions.dart \\');
    print('    /path/to/project \\');
    print('    /path/to/project/lib/controller.dart \\');
    print('    17');
    exit(1);
  }

  final workspace = args[0];
  final file = args[1];
  final line = int.parse(args[2]);
  final character = args.length > 3 ? int.parse(args[3]) : 0;

  print('Workspace: $workspace');
  print('File: $file');
  print('Position: line $line, char $character');
  print('');

  // Start language server from workspace directory
  // Try using snapshot directly - might have better plugin support
  final dartPath = Platform.resolvedExecutable; // path to dart
  final sdkBin = File(dartPath).parent.path;
  final snapshotPath = '$sdkBin/snapshots/analysis_server.dart.snapshot';

  final useSnapshot = await File(snapshotPath).exists();

  print('Starting analysis server from workspace...');
  print('Using: ${useSnapshot ? 'snapshot' : 'dart language-server'}');

  // Use dart language-server with diagnostic port
  final process = await Process.start(
    'dart',
    [
      'language-server',
      '--protocol=lsp',
      '--client-id=test',
      '--client-version=1.0.0',
      '--diagnostic-port=9200',
    ],
    workingDirectory: workspace,
  );

  print('Diagnostic UI: http://localhost:9200');

  final pending = <int, Completer<dynamic>>{};
  var msgId = 0;

  // Log stderr
  process.stderr.transform(utf8.decoder).listen((data) {
    print('[STDERR] $data');
  });

  // Parse messages
  final buffer = StringBuffer();
  process.stdout.transform(utf8.decoder).listen((chunk) {
    // Log raw chunk length for debugging
    print('[RAW CHUNK] ${chunk.length} bytes');
    buffer.write(chunk);
    while (true) {
      final content = buffer.toString();
      final headerEnd = content.indexOf('\r\n\r\n');
      if (headerEnd == -1) {
        print('[PARSE] No header end found, buffer size: ${content.length}');
        break;
      }
      final header = content.substring(0, headerEnd);
      final lengthMatch = RegExp(r'Content-Length: (\d+)').firstMatch(header);
      if (lengthMatch == null) break;
      final length = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      print('[PARSE] Content-Length: $length, bodyStart: $bodyStart, bufferLen: ${content.length}, need: ${bodyStart + length}');
      String body;
      if (content.length < bodyStart + length) {
        // Try parsing anyway if we're close (within 10 bytes) - workaround for truncated responses
        final missing = bodyStart + length - content.length;
        if (missing <= 10) {
          print('[PARSE] Missing $missing bytes, trying to parse available data...');
          body = content.substring(bodyStart);
          // Clear buffer for this workaround
          buffer.clear();
        } else {
          break;
        }
      } else {
        body = content.substring(bodyStart, bodyStart + length);
        buffer.clear();
        buffer.write(content.substring(bodyStart + length));
      }

      final msg = jsonDecode(body) as Map<String, dynamic>;

      // Debug: log raw message type
      if (msg.containsKey('id') && (msg.containsKey('result') || msg.containsKey('error'))) {
        print('[RAW RESPONSE] id=${msg['id']} (${msg['id'].runtimeType}), hasResult=${msg.containsKey('result')}, hasError=${msg.containsKey('error')}');
      }

      // Handle response
      if (msg.containsKey('id') && msg.containsKey('result')) {
        final id = msg['id'];
        // Handle both int and string IDs
        final intId = id is int ? id : int.tryParse(id.toString());
        print('[DEBUG] Response id=$id (intId=$intId), pending keys: ${pending.keys.toList()}');
        if (intId != null) {
          if (pending.containsKey(intId)) {
            pending.remove(intId)!.complete(msg['result']);
          } else {
            print('[DEBUG] WARNING: No pending request for id=$intId');
          }
        }
      } else if (msg.containsKey('id') && msg.containsKey('error')) {
        print('[ERROR] ${msg['error']}');
        pending[msg['id'] as int]?.completeError(msg['error'] as Object);
      } else if (msg.containsKey('id') && msg.containsKey('method')) {
        // Server request - respond
        final method = msg['method'] as String;
        print('[SERVER REQUEST] $method');
        dynamic result;
        if (method == 'workspace/configuration') {
          final items = (msg['params']['items'] as List?) ?? [];
          result = [for (final _ in items) <String, dynamic>{}];
        }
        final resp = jsonEncode({'jsonrpc': '2.0', 'id': msg['id'], 'result': result});
        process.stdin.write('Content-Length: ${resp.length}\r\n\r\n$resp');
      } else if (msg.containsKey('method')) {
        // Notification - log ALL
        final method = msg['method'] as String;
        final params = msg['params'];
        final paramsStr = params != null ? jsonEncode(params) : '';
        final preview = paramsStr.length > 100 ? '${paramsStr.substring(0, 100)}...' : paramsStr;
        print('[NOTIFICATION] $method: $preview');
      }
    }
  });

  Future<dynamic> request(String method, Map<String, dynamic> params) async {
    final id = msgId++;
    final completer = Completer<dynamic>();
    pending[id] = completer;
    final m = jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    print('[DEBUG] Sending request id=$id method=$method');
    process.stdin.write('Content-Length: ${m.length}\r\n\r\n$m');
    await process.stdin.flush();
    return completer.future.timeout(const Duration(seconds: 60));
  }

  void notify(String method, Map<String, dynamic> params) {
    final m = jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params});
    process.stdin.write('Content-Length: ${m.length}\r\n\r\n$m');
  }

  final rootUri = Uri.directory(workspace).toString();

  print('Sending initialize...');
  await request('initialize', {
    'processId': pid,
    'rootUri': rootUri,
    'workspaceFolders': [{'uri': rootUri, 'name': workspace.split('/').last}],
    'capabilities': {
      'textDocument': {'codeAction': {'codeActionLiteralSupport': {'codeActionKind': {'valueSet': ['quickfix', 'refactor', 'source']}}}},
      'workspace': {'applyEdit': true, 'workspaceFolders': true, 'configuration': true},
    },
  });

  notify('initialized', {});
  print('Waiting 8 seconds for analysis + plugin loading...');
  await Future<void>.delayed(const Duration(seconds: 8));

  print('\nOpening file...');
  final content = await File(file).readAsString();
  notify('textDocument/didOpen', {
    'textDocument': {'uri': Uri.file(file).toString(), 'languageId': 'dart', 'version': 1, 'text': content},
  });
  await Future<void>.delayed(const Duration(seconds: 2));

  print('Getting code actions at line $line, char $character...\n');

  // First request - triggers plugin
  print('First request (all actions)...');
  final actions1 = await request('textDocument/codeAction', {
    'textDocument': {'uri': Uri.file(file).toString()},
    'range': {'start': {'line': line, 'character': character}, 'end': {'line': line, 'character': character}},
    'context': {'diagnostics': <dynamic>[]},
  });
  print('First request - Found ${(actions1 as List).length} actions:');
  for (final a in actions1) {
    print('  - ${a['title']} (${a['kind']})');
  }

  // Wait for plugin
  print('\nWaiting 3 seconds for plugin...');
  await Future<void>.delayed(const Duration(seconds: 3));

  // Second request - should include plugin assists
  print('\nSecond request (all actions):');
  final actions = await request('textDocument/codeAction', {
    'textDocument': {'uri': Uri.file(file).toString()},
    'range': {'start': {'line': line, 'character': character}, 'end': {'line': line, 'character': character}},
    'context': {'diagnostics': <dynamic>[]},
  });

  print('Found ${(actions as List).length} actions:');
  for (final a in actions) {
    print('  - ${a['title']} (${a['kind']})');
  }

  print('\n>>> Open http://localhost:9200 to see diagnostics <<<');
  print('Press Enter to exit...');
  stdin.readLineSync();

  process.kill();
  exit(0);
}
