// Test-only FIT decoder (S02 plan U19). Independent of the production encoder:
// its CRC is the bitwise CRC-16/ARC (polynomial 0xA001 reflected, initial 0)
// that the FIT SDK defines, not the encoder's nibble table. It checks the
// header size, protocol, ".FIT" signature, header CRC, data size, file CRC,
// reads definition messages (little and big endian) and decodes data messages
// field by field, mapping the FIT "invalid" value of each base type to null.
import 'dart:typed_data';

/// CRC-16/ARC, bit by bit. Known vector: "123456789" -> 0xBB3D.
int fitTestCrc(List<int> bytes, [int start = 0, int? end]) {
  var crc = 0;
  for (var i = start; i < (end ?? bytes.length); i++) {
    crc ^= bytes[i] & 0xFF;
    for (var b = 0; b < 8; b++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc & 0xFFFF;
}

class FitMessage {
  FitMessage(this.globalNum, this.fields);

  final int globalNum;

  /// Field number -> decoded value (int, double, String, List) or null when the
  /// value is the FIT invalid value of its base type.
  final Map<int, Object?> fields;

  int? intField(int n) {
    final v = fields[n];
    return v is int ? v : null;
  }
}

class FitDecoded {
  final List<FitMessage> messages = [];
  final List<String> errors = [];

  int headerSize = 0;
  int protocolVersion = 0;
  int profileVersion = 0;
  int dataSize = 0;
  bool signatureOk = false;
  bool headerCrcOk = false;
  bool fileCrcOk = false;

  /// True when no structural problem was found.
  bool get ok => errors.isEmpty && signatureOk && headerCrcOk && fileCrcOk;

  List<FitMessage> byNum(int n) =>
      [for (final m in messages) if (m.globalNum == n) m];
}

class _Def {
  _Def(this.globalNum, this.little, this.fields);
  final int globalNum;
  final bool little;
  final List<(int num, int size, int type)> fields;
}

/// Decodes [bytes]; never throws, problems land in [FitDecoded.errors].
FitDecoded decodeFit(Uint8List bytes) {
  final r = FitDecoded();
  if (bytes.length < 14) {
    r.errors.add('file shorter than a header');
    return r;
  }
  r.headerSize = bytes[0];
  r.protocolVersion = bytes[1];
  r.profileVersion = bytes[2] | (bytes[3] << 8);
  r.dataSize = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
  r.signatureOk = bytes[8] == 0x2E && bytes[9] == 0x46 && bytes[10] == 0x49 && bytes[11] == 0x54;
  if (r.headerSize != 12 && r.headerSize != 14) {
    r.errors.add('bad header size ${r.headerSize}');
    return r;
  }
  if (r.headerSize == 14) {
    final stored = bytes[12] | (bytes[13] << 8);
    r.headerCrcOk = stored == fitTestCrc(bytes, 0, 12);
  } else {
    r.headerCrcOk = true;
  }
  final end = r.headerSize + r.dataSize;
  if (bytes.length != end + 2) {
    r.errors.add('length ${bytes.length} != header + data + crc = ${end + 2}');
    return r;
  }
  final fileCrc = bytes[end] | (bytes[end + 1] << 8);
  r.fileCrcOk = fileCrc == fitTestCrc(bytes, 0, end);
  if (!r.fileCrcOk || !r.headerCrcOk) {
    r.errors.add('crc failure (header ok: ${r.headerCrcOk}, file ok: ${r.fileCrcOk})');
    return r;
  }

  final defs = <int, _Def>{};
  var p = r.headerSize;
  final bd = ByteData.sublistView(bytes);
  while (p < end) {
    final h = bytes[p++];
    if ((h & 0x80) != 0) {
      r.errors.add('compressed timestamp header at ${p - 1} not supported');
      return r;
    }
    final local = h & 0x0F;
    if ((h & 0x40) != 0) {
      if (p + 5 > end) {
        r.errors.add('truncated definition');
        return r;
      }
      p++; // reserved
      final little = bytes[p++] == 0;
      final g = little ? bd.getUint16(p, Endian.little) : bd.getUint16(p, Endian.big);
      p += 2;
      final n = bytes[p++];
      final fields = <(int, int, int)>[];
      if (p + n * 3 > end) {
        r.errors.add('truncated definition fields');
        return r;
      }
      for (var i = 0; i < n; i++) {
        fields.add((bytes[p], bytes[p + 1], bytes[p + 2]));
        p += 3;
      }
      if ((h & 0x20) != 0) {
        final dn = bytes[p++];
        p += dn * 3;
      }
      defs[local] = _Def(g, little, fields);
    } else {
      final d = defs[local];
      if (d == null) {
        r.errors.add('data message for undefined local type $local');
        return r;
      }
      final values = <int, Object?>{};
      for (final (num, size, type) in d.fields) {
        if (p + size > end) {
          r.errors.add('truncated data message');
          return r;
        }
        values[num] = _value(bd, p, size, type, d.little);
        p += size;
      }
      r.messages.add(FitMessage(d.globalNum, values));
    }
  }
  if (p != end) r.errors.add('data size mismatch');
  return r;
}

Object? _value(ByteData bd, int p, int size, int type, bool little) {
  final e = little ? Endian.little : Endian.big;
  final base = type & 0x1F;
  switch (base) {
    case 0: // enum
    case 2: // uint8
    case 13: // byte
      if (size != 1) return null;
      final v = bd.getUint8(p);
      return v == 0xFF ? null : v;
    case 1: // sint8
      final v = bd.getInt8(p);
      return v == 0x7F ? null : v;
    case 3: // sint16
      final v = bd.getInt16(p, e);
      return v == 0x7FFF ? null : v;
    case 4: // uint16
      final v = bd.getUint16(p, e);
      return v == 0xFFFF ? null : v;
    case 5: // sint32
      final v = bd.getInt32(p, e);
      return v == 0x7FFFFFFF ? null : v;
    case 6: // uint32
      final v = bd.getUint32(p, e);
      return v == 0xFFFFFFFF ? null : v;
    case 7: // string
      final raw = [for (var i = 0; i < size; i++) bd.getUint8(p + i)];
      final z = raw.indexOf(0);
      return String.fromCharCodes(z < 0 ? raw : raw.sublist(0, z));
    default:
      return null;
  }
}
