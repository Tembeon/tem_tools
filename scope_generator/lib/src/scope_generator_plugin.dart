import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:scope_generator/src/add_aspect_assist.dart';
import 'package:scope_generator/src/generate_scope_assist.dart';

/// Plugin that provides Quick Assists for Scope pattern:
/// - Generate Scope wrapper from Listenable-based controller
/// - Expose State field as Scope aspect
class ScopeGeneratorPlugin extends Plugin {
  @override
  String get name => 'scope_generator';

  @override
  void register(PluginRegistry registry) {
    registry.registerAssist(GenerateScopeAssist.new);
    registry.registerAssist(AddAspectAssist.new);
  }
}
