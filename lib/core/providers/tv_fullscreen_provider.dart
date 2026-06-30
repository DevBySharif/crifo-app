import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the fullscreen widget when TV is in fullscreen mode.
/// MainShell watches this and renders it as a Stack overlay above BottomNav.
final tvFullscreenProvider = StateProvider<Widget?>((ref) => null);
