import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the fullscreen widget when TV is in fullscreen mode.
/// MainShell watches this and renders it as a Stack overlay above BottomNav.
final tvFullscreenProvider = StateProvider<Widget?>((ref) => null);

/// Requests the TV tab to play a channel by id.
/// Set from anywhere (e.g. match detail "Where to watch"); MainShell switches
/// to the TV tab and TVScreen picks it up, plays it, then clears the request.
final tvPlayRequestProvider = StateProvider<String?>((ref) => null);
