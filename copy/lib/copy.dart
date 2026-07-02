/// {@macro copy}
library;

export 'src/copy_extension.dart';
// In Flutter builds (dart:ui available) re-export Flutter's own ValueGetter
// so that importing this package together with Flutter causes no name
// ambiguity. The URI resolves through the consuming app's package config;
// outside Flutter the branch is never compiled and the local stub is used.
export 'src/value_getter.dart'
    if (dart.library.ui) 'package:flutter/foundation.dart' // ignore: conditional_uri_does_not_exist
    show ValueGetter;
