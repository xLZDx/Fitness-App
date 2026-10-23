import 'dart:convert';

import 'data_export_sink.dart';
import 'server_export.dart';

/// Writes the export JSON to [out] in pieces. [data] is the [buildExport]
/// result whose `server` entry is the outcome's header; when [server] is given
/// that entry is written as the header plus every paged section streamed from
/// disk, one row at a time, so neither all rows nor the whole JSON text is ever
/// in memory. Top-level shape and key order are those of [buildExport].
Future<void> writeExportJsonStreamed({
  required ExportTextSink out,
  required Map<String, dynamic> data,
  ServerExportOutcome? server,
}) async {
  const indent = JsonEncoder.withIndent('  ');
  await out.write('{\n');
  var first = true;
  for (final e in data.entries) {
    if (!first) await out.write(',\n');
    first = false;
    await out.write('${jsonEncode(e.key)}: ');
    if (e.key == 'server' && server != null) {
      await _writeServer(out, server);
    } else {
      await out.write(indent.convert(e.value));
    }
  }
  await out.write('\n}\n');
}

Future<void> _writeServer(ExportTextSink out, ServerExportOutcome server) async {
  await out.write('{');
  var first = true;
  for (final e in server.header.entries) {
    await out.write('${first ? '\n' : ',\n'}${jsonEncode(e.key)}: ');
    first = false;
    await out.write(jsonEncode(e.value));
  }
  for (final section in server.sections) {
    await out.write('${first ? '\n' : ',\n'}${jsonEncode(section)}: [');
    first = false;
    var firstRow = true;
    await for (final row in server.rows(section)) {
      await out.write('${firstRow ? '\n' : ',\n'}${jsonEncode(row)}');
      firstRow = false;
    }
    await out.write(firstRow ? ']' : '\n]');
  }
  await out.write('\n}');
}
