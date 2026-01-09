/// Analysis server plugin to generate Flutter Scope boilerplate
/// from Listenable-based controllers.
///
/// ## Usage
///
/// Add to your `analysis_options.yaml`:
/// ```yaml
/// plugins:
///   scope_generator:
///     path: /path/to/scope_generator
/// ```
///
/// Then restart the Analysis Server.
///
/// ## How it works
///
/// 1. Write a controller class extending `Listenable` (e.g., `ValueNotifier<T>`)
/// 2. Place cursor on the class name
/// 3. IDE shows "Generate Scope wrapper" assist
/// 4. Click to generate the full Scope boilerplate
library;

import 'package:scope_generator/src/scope_generator_plugin.dart';

/// The plugin instance used by the analysis server.
final plugin = ScopeGeneratorPlugin();
