import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:scope_generator/src/generate_scope_assist.dart';

/// Plugin that provides a Quick Assist to generate Scope boilerplate
/// from Listenable-based controller classes.
class ScopeGeneratorPlugin extends Plugin {
  @override
  String get name => 'scope_generator';

  @override
  void register(PluginRegistry registry) {
    registry.registerAssist(GenerateScopeAssist.new);
  }
}
