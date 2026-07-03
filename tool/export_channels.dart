import 'dart:convert';
import 'dart:io';
import '../lib/core/api/tv_channels.dart';

// Dumps the built-in channel list to football-eon-web/public/channels.json.
// Run:  dart run tool/export_channels.dart
void main() {
  final list = tvChannels
      .map((c) => {
            'id': c.id,
            'name': c.name,
            'category': c.category.name,
            'streamUrl': c.streamUrl,
            'logoUrl': c.logoUrl,
          })
      .toList();
  final out = {'version': 1, 'count': list.length, 'channels': list};
  final json = const JsonEncoder.withIndent('').convert(out);
  final path = r'D:\Android App\ScoreApp\football-eon-web\public\channels.json';
  File(path).writeAsStringSync(json);
  stdout.writeln('wrote ${list.length} channels to $path');
}
