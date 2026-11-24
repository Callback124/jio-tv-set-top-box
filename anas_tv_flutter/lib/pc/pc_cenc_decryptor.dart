import 'dart:convert';
import 'dart:typed_data';

class PcTrackCrypto {
  final int trackId;
  final String initPath;
  final String originalCodec;
  final String scheme; // 'cenc', 'cbcs', 'cens', 'cbc1'
  final int ivSize;
  final String kidHex;
  final Uint8List constantIv;
  final int cryptByteBlock;
  final int skipByteBlock;

  const PcTrackCrypto({
    required this.trackId,
    required this.initPath,
    required this.originalCodec,
    required this.scheme,
    required this.ivSize,
    required this.kidHex,
    required this.constantIv,
    required this.cryptByteBlock,
    required this.skipByteBlock,
  });

  PcTrackCrypto copyWith({String? initPath}) {
    return PcTrackCrypto(
      trackId: trackId,
      initPath: initPath ?? this.initPath,
      originalCodec: originalCodec,
      scheme: scheme,
      ivSize: ivSize,
      kidHex: kidHex,
      constantIv: constantIv,
      cryptByteBlock: cryptByteBlock,
      skipByteBlock: skipByteBlock,
    );
  }
}

class PcTrackCryptoStore {
  final List<PcTrackCrypto> _entries = [];

  void add(PcTrackCrypto entry) {
    _entries.removeWhere(
      (e) => e.initPath == entry.initPath && e.trackId == entry.trackId,
    );
    _entries.add(entry);
    if (_entries.length > 32) {
      _entries.removeAt(0);
    }
  }

  PcTrackCrypto? findBest(String segmentPath, int trackId) {
    if (_entries.isEmpty) return null;
    PcTrackCrypto? best;
    var bestScore = -1;
    final segDir = _dirOf(segmentPath);
    for (final e in _entries) {
      var score = 0;
      if (trackId > 0 && e.trackId == trackId) score += 10;
      final initDir = _dirOf(e.initPath);
      if (initDir.isNotEmpty && segDir == initDir) {
        score += 1000;
      } else {
        score += _commonPrefixLen(segDir, initDir) * 2;
      }
      score += _commonPrefixLen(segmentPath, e.initPath);
      if (score > bestScore) {
        bestScore = score;
        best = e;
      }
    }
    return best ?? _entries.last;
  }

  static String _dirOf(String p) {
    final idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(0, idx + 1) : '';
  }

  static int _commonPrefixLen(String a, String b) {
    final limit = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < limit && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }
}

class _BoxHeader {
  final int offset;
  final int size;
  final int headerSize;
  final String type;

  const _BoxHeader({
    required this.offset,
    required this.size,
    required this.headerSize,
    required this.type,
  });

  int get payloadOffset => offset + headerSize;
  int get payloadSize => size - headerSize;
  int get end => offset + size;
}

class PcCencDecryptor {
  static const List<int> _piffUuid = [
    0xa2, 0x39, 0x4f, 0x52, 0x5a, 0x9b, 0x4f, 0x14,
    0xa2, 0x44, 0x6c, 0x42, 0x7c, 0x64, 0x8d, 0xf4,
  ];

  static int _u16(Uint8List b, int o) => ((b[o] & 0xFF) << 8) | (b[o + 1] & 0xFF);

  static int _u32(Uint8List b, int o) =>
      ((b[o] & 0xFF) << 24) |
      ((b[o + 1] & 0xFF) << 16) |
      ((b[o + 2] & 0xFF) << 8) |
      (b[o + 3] & 0xFF);

  static int _i32(Uint8List b, int o) {
    final v = _u32(b, o);
    return (v & 0x80000000) != 0 ? v - 0x100000000 : v;
  }

  static void _writeU32(Uint8List b, int o, int val) {
    b[o] = (val >> 24) & 0xFF;
    b[o + 1] = (val >> 16) & 0xFF;
    b[o + 2] = (val >> 8) & 0xFF;
    b[o + 3] = val & 0xFF;
  }

  static String _fourCc(Uint8List b, int o) =>
      String.fromCharCodes(b.sublist(o, o + 4));

  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final v in bytes) {
      sb.write((v & 0xFF).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List? _hexToBytes(String raw) {
    final clean = raw.trim().replaceAll('-', '').toLowerCase();
    if (clean.length == 32 && RegExp(r'^[0-9a-f]{32}$').hasMatch(clean)) {
      final out = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }
    try {
      var b64 = raw.trim().replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final bytes = base64Decode(b64);
      if (bytes.length == 16) return Uint8List.fromList(bytes);
    } catch (_) {}
    return null;
  }

  static _BoxHeader? _readBox(Uint8List b, int offset, int limit) {
    if (offset + 8 > limit) return null;
    var size = _u32(b, offset);
    final type = _fourCc(b, offset + 4);
    var headerSize = 8;
    if (size == 1) {
      if (offset + 16 > limit) return null;
      final hi = _u32(b, offset + 8);
      final lo = _u32(b, offset + 12);
      size = (hi * 0x100000000) + lo;
      headerSize = 16;
    } else if (size == 0) {
      size = limit - offset;
    }
    if (size < headerSize || offset + size > limit) return null;
    return _BoxHeader(offset: offset, size: size, headerSize: headerSize, type: type);
  }

  static List<_BoxHeader> _children(Uint8List b, int start, int end) {
    final list = <_BoxHeader>[];
    var pos = start;
    while (pos + 8 <= end) {
      final box = _readBox(b, pos, end);
      if (box == null) break;
      list.add(box);
      pos = box.end;
    }
    return list;
  }

  /// Strips `sinf` and restores `encv`/`enca` -> original codec (`hvc1`, `mp4a`, etc.)
  /// in init segments (`moov`), and records track crypto metadata keyed by URL path & trackId.
  static Uint8List processInitSegment(
    Uint8List input,
    String urlPath,
    PcTrackCryptoStore store,
  ) {
    if (input.length < 16) return input;
    final topBoxes = _children(input, 0, input.length);
    if (!topBoxes.any((b) => b.type == 'moov')) return input;

    final out = BytesBuilder(copy: false);
    for (final box in topBoxes) {
      if (box.type == 'moov') {
        out.add(_rebuildMoov(input, box, urlPath, store));
      } else {
        out.add(Uint8List.sublistView(input, box.offset, box.end));
      }
    }
    return out.toBytes();
  }

  static Uint8List _wrapBox(String type, Uint8List payload) {
    final out = Uint8List(8 + payload.length);
    _writeU32(out, 0, out.length);
    out.setRange(4, 8, type.codeUnits.take(4));
    out.setRange(8, out.length, payload);
    return out;
  }

  static Uint8List _rebuildMoov(
    Uint8List src,
    _BoxHeader moov,
    String urlPath,
    PcTrackCryptoStore store,
  ) {
    final payload = BytesBuilder(copy: false);
    for (final child in _children(src, moov.payloadOffset, moov.end)) {
      if (child.type == 'trak') {
        payload.add(_rebuildTrak(src, child, urlPath, store));
      } else {
        payload.add(Uint8List.sublistView(src, child.offset, child.end));
      }
    }
    return _wrapBox('moov', payload.toBytes());
  }

  static Uint8List _rebuildTrak(
    Uint8List src,
    _BoxHeader trak,
    String urlPath,
    PcTrackCryptoStore store,
  ) {
    var trackId = 0;
    final children = _children(src, trak.payloadOffset, trak.end);
    for (final c in children) {
      if (c.type == 'tkhd' && c.payloadSize >= 24) {
        final ver = src[c.payloadOffset];
        final idOff = c.payloadOffset + (ver == 1 ? 20 : 12);
        if (idOff + 4 <= c.end) trackId = _u32(src, idOff);
        break;
      }
    }
    final payload = BytesBuilder(copy: false);
    for (final c in children) {
      if (c.type == 'mdia') {
        payload.add(_rebuildContainer(src, c, 'minf', (minf) {
          return _rebuildContainer(src, minf, 'stbl', (stbl) {
            return _rebuildContainer(src, stbl, 'stsd', (stsd) {
              return _rebuildStsd(src, stsd, trackId, urlPath, store);
            });
          });
        }));
      } else {
        payload.add(Uint8List.sublistView(src, c.offset, c.end));
      }
    }
    return _wrapBox('trak', payload.toBytes());
  }

  static Uint8List _rebuildContainer(
    Uint8List src,
    _BoxHeader container,
    String targetChild,
    Uint8List Function(_BoxHeader) transform,
  ) {
    final payload = BytesBuilder(copy: false);
    for (final c in _children(src, container.payloadOffset, container.end)) {
      if (c.type == targetChild) {
        payload.add(transform(c));
      } else {
        payload.add(Uint8List.sublistView(src, c.offset, c.end));
      }
    }
    return _wrapBox(container.type, payload.toBytes());
  }

  static Uint8List _rebuildStsd(
    Uint8List src,
    _BoxHeader stsd,
    int trackId,
    String urlPath,
    PcTrackCryptoStore store,
  ) {
    if (stsd.payloadSize < 8) {
      return Uint8List.sublistView(src, stsd.offset, stsd.end);
    }
    final payload = BytesBuilder(copy: false);
    payload.add(Uint8List.sublistView(src, stsd.payloadOffset, stsd.payloadOffset + 8));
    for (final entry in _children(src, stsd.payloadOffset + 8, stsd.end)) {
      if (entry.type == 'encv' || entry.type == 'enca' || entry.type == 'encs') {
        payload.add(_rebuildEncryptedSampleEntry(src, entry, trackId, urlPath, store));
      } else {
        payload.add(Uint8List.sublistView(src, entry.offset, entry.end));
      }
    }
    return _wrapBox('stsd', payload.toBytes());
  }

  static int _sampleEntryFixedBytes(Uint8List src, _BoxHeader entry) {
    if (entry.type == 'encv') return 78;
    if (entry.type == 'enca') {
      for (final candidate in const [28, 44, 64]) {
        if (entry.payloadOffset + candidate + 8 <= entry.end) {
          final children = _children(src, entry.payloadOffset + candidate, entry.end);
          if (children.any((b) =>
              b.type == 'sinf' || b.type == 'esds' || b.type == 'dac3' || b.type == 'dec3')) {
            return candidate;
          }
        }
      }
      return 28;
    }
    return 8;
  }

  static Uint8List _rebuildEncryptedSampleEntry(
    Uint8List src,
    _BoxHeader entry,
    int trackId,
    String urlPath,
    PcTrackCryptoStore store,
  ) {
    final fixedLen = _sampleEntryFixedBytes(src, entry);
    if (entry.payloadSize < fixedLen) {
      return Uint8List.sublistView(src, entry.offset, entry.end);
    }

    var originalCodec = entry.type == 'encv' ? 'hvc1' : 'mp4a';
    var scheme = 'cenc';
    var ivSize = 8;
    var kidHex = '';
    var constantIv = Uint8List(0);
    var cryptBlocks = 0;
    var skipBlocks = 0;

    final children = _children(src, entry.payloadOffset + fixedLen, entry.end);
    final keptChildren = BytesBuilder(copy: false);

    for (final c in children) {
      if (c.type != 'sinf') {
        keptChildren.add(Uint8List.sublistView(src, c.offset, c.end));
        continue;
      }

      for (final sc in _children(src, c.payloadOffset, c.end)) {
        if (sc.type == 'frma' && sc.payloadSize >= 4) {
          originalCodec = _fourCc(src, sc.payloadOffset);
        } else if (sc.type == 'schm' && sc.payloadSize >= 8) {
          scheme = _fourCc(src, sc.payloadOffset + 4);
        } else if (sc.type == 'schi') {
          for (final tenc in _children(src, sc.payloadOffset, sc.end)) {
            if (tenc.type == 'tenc' && tenc.payloadSize >= 24) {
              final p = tenc.payloadOffset;
              final ver = src[p];
              if (ver >= 1) {
                final pattern = src[p + 5];
                cryptBlocks = (pattern >> 4) & 0x0F;
                skipBlocks = pattern & 0x0F;
              }
              ivSize = src[p + 7];
              kidHex = _toHex(Uint8List.sublistView(src, p + 8, p + 24));
              if (ivSize == 0 && tenc.payloadSize >= 25) {
                final civLen = src[p + 24];
                if (tenc.payloadSize >= 25 + civLen) {
                  constantIv = Uint8List.fromList(
                    Uint8List.sublistView(src, p + 25, p + 25 + civLen),
                  );
                }
              }
            }
          }
        }
      }
    }

    store.add(PcTrackCrypto(
      trackId: trackId,
      initPath: urlPath,
      originalCodec: originalCodec,
      scheme: scheme,
      ivSize: ivSize,
      kidHex: kidHex,
      constantIv: constantIv,
      cryptByteBlock: cryptBlocks,
      skipByteBlock: skipBlocks,
    ));

    final inner = BytesBuilder(copy: false);
    inner.add(Uint8List.sublistView(src, entry.payloadOffset, entry.payloadOffset + fixedLen));
    inner.add(keptChildren.toBytes());
    return _wrapBox(originalCodec, inner.toBytes());
  }

  static String _extractSeigKid(Uint8List buf, _BoxHeader sgpd) {
    // FullBox: version(1) + flags(3) + grouping_type(4)
    if (sgpd.payloadSize < 16) return '';
    final ver = buf[sgpd.payloadOffset];
    final groupingType = _fourCc(buf, sgpd.payloadOffset + 4);
    if (groupingType != 'seig') return '';
    var cursor = sgpd.payloadOffset + 8;
    if (ver >= 1) cursor += 4; // default_length
    if (cursor + 4 > sgpd.end) return '';
    final entryCount = _u32(buf, cursor);
    cursor += 4;
    if (entryCount < 1) return '';
    if (ver >= 1 && cursor + 4 <= sgpd.end) {
      // If default_length == 0, description_length precedes entry; check payload len
      if (sgpd.end - cursor >= 24 && buf[cursor + 4] <= 1 && buf[cursor + 5] <= 16) {
        // Already CencSampleEncryptionInformationGroupEntry without length? Try standard offset.
      }
    }
    // CencSampleEncryptionInformationGroupEntry:
    // reserved(1), pattern(1), isProtected(1), perSampleIVSize(1), KID(16)
    if (cursor + 20 <= sgpd.end && (buf[cursor + 2] == 1 || buf[cursor + 2] == 0)) {
      return _toHex(Uint8List.sublistView(buf, cursor + 4, cursor + 20));
    }
    if (cursor + 24 <= sgpd.end && (buf[cursor + 6] == 1 || buf[cursor + 6] == 0)) {
      return _toHex(Uint8List.sublistView(buf, cursor + 8, cursor + 24));
    }
    return '';
  }

  /// Decrypts CENC/CBCS media segments (`moof` + `mdat`) in-place using [clearKeys].
  static Uint8List processMediaSegment(
    Uint8List input,
    String urlPath,
    PcTrackCryptoStore store,
    Map<String, String> clearKeys,
  ) {
    if (input.length < 24 || clearKeys.isEmpty) return input;
    final topBoxes = _children(input, 0, input.length);
    if (!topBoxes.any((b) => b.type == 'moof') || !topBoxes.any((b) => b.type == 'mdat')) {
      return input;
    }

    final normalizedKeys = <String, Uint8List>{};
    clearKeys.forEach((k, v) {
      final kb = _hexToBytes(k);
      final vb = _hexToBytes(v);
      if (kb != null && vb != null) {
        normalizedKeys[_toHex(kb)] = vb;
      }
    });
    if (normalizedKeys.isEmpty) return input;

    final out = Uint8List.fromList(input);

    for (var bi = 0; bi < topBoxes.length; bi++) {
      final moof = topBoxes[bi];
      if (moof.type != 'moof') continue;

      _BoxHeader? nextMdat;
      for (var mj = bi + 1; mj < topBoxes.length; mj++) {
        if (topBoxes[mj].type == 'mdat') {
          nextMdat = topBoxes[mj];
          break;
        }
      }
      if (nextMdat == null) continue;

      for (final traf in _children(out, moof.payloadOffset, moof.end)) {
        if (traf.type != 'traf') continue;

        final trafKids = _children(out, traf.payloadOffset, traf.end);
        var trackId = 0;
        var defaultSampleSize = 0;
        final sampleSizes = <int>[];
        int? firstTrunDataOffset;
        _BoxHeader? sencBox;
        var sencIsPiff = false;
        var seigKidHex = '';

        for (final tb in trafKids) {
          if (tb.type == 'tfhd' && tb.payloadSize >= 8) {
            final flags = _u32(out, tb.payloadOffset) & 0x00FFFFFF;
            trackId = _u32(out, tb.payloadOffset + 4);
            var cursor = tb.payloadOffset + 8;
            if ((flags & 0x01) != 0) cursor += 8;
            if ((flags & 0x02) != 0) cursor += 4;
            if ((flags & 0x08) != 0) cursor += 4;
            if ((flags & 0x10) != 0 && cursor + 4 <= tb.end) {
              defaultSampleSize = _u32(out, cursor);
            }
          } else if (tb.type == 'trun' && tb.payloadSize >= 8) {
            final flags = _u32(out, tb.payloadOffset) & 0x00FFFFFF;
            final count = _u32(out, tb.payloadOffset + 4);
            var cursor = tb.payloadOffset + 8;
            if ((flags & 0x01) != 0 && cursor + 4 <= tb.end) {
              final dOff = _i32(out, cursor);
              firstTrunDataOffset ??= dOff;
              cursor += 4;
            }
            if ((flags & 0x04) != 0) cursor += 4;
            final hasDur = (flags & 0x100) != 0;
            final hasSize = (flags & 0x200) != 0;
            final hasFlags = (flags & 0x400) != 0;
            final hasCto = (flags & 0x800) != 0;
            for (var si = 0; si < count; si++) {
              if (hasDur) cursor += 4;
              var sz = defaultSampleSize;
              if (hasSize && cursor + 4 <= tb.end) {
                sz = _u32(out, cursor);
                cursor += 4;
              }
              if (hasFlags) cursor += 4;
              if (hasCto) cursor += 4;
              sampleSizes.add(sz);
            }
          } else if (tb.type == 'sgpd' && seigKidHex.isEmpty) {
            seigKidHex = _extractSeigKid(out, tb);
          } else if (tb.type == 'senc') {
            sencBox = tb;
          } else if (tb.type == 'uuid' && tb.payloadSize >= 24) {
            var match = true;
            for (var ui = 0; ui < 16; ui++) {
              if (out[tb.payloadOffset + ui] != _piffUuid[ui]) {
                match = false;
                break;
              }
            }
            if (match) {
              sencBox = tb;
              sencIsPiff = true;
            }
          }
        }

        if (sencBox == null) continue;

        final crypto = store.findBest(urlPath, trackId);
        final scheme = crypto?.scheme ?? 'cenc';
        var ivSize = crypto?.ivSize ?? 8;
        final constantIv = crypto?.constantIv ?? Uint8List(0);
        final cryptBlocks = crypto?.cryptByteBlock ?? 0;
        final skipBlocks = crypto?.skipByteBlock ?? 0;

        Uint8List? aesKey;
        if (seigKidHex.isNotEmpty) {
          aesKey = normalizedKeys[seigKidHex];
        }
        if (aesKey == null && crypto != null && crypto.kidHex.isNotEmpty) {
          aesKey = normalizedKeys[crypto.kidHex];
        }
        if (aesKey == null && normalizedKeys.length == 1) {
          aesKey = normalizedKeys.values.first;
        }
        if (aesKey == null && normalizedKeys.isNotEmpty) {
          aesKey = normalizedKeys.values.first;
        }
        if (aesKey == null) continue;

        final headerSkip = sencIsPiff ? 16 : 0;
        if (sencBox.payloadSize < headerSkip + 8) continue;
        final sp = sencBox.payloadOffset + headerSkip;
        final sencFlags = _u32(out, sp) & 0x00FFFFFF;
        final sampleCount = _u32(out, sp + 4);
        final useSubsamples = (sencFlags & 0x02) != 0;

        var sampleCursor = firstTrunDataOffset != null
            ? (moof.offset + firstTrunDataOffset)
            : nextMdat.payloadOffset;
        if (sampleCursor < nextMdat.payloadOffset || sampleCursor >= nextMdat.end) {
          sampleCursor = nextMdat.payloadOffset;
        }

        var sc = sp + 8;
        final sencEnd = sencBox.end;

        if (crypto == null && sampleCount > 0 && !useSubsamples) {
          final rem = sencEnd - sc;
          if (rem == sampleCount * 16) ivSize = 16;
          else if (rem == sampleCount * 8) ivSize = 8;
        }

        final aes = _Aes128(aesKey);

        for (var i = 0; i < sampleCount; i++) {
          if (sc + ivSize > sencEnd) break;
          final iv = Uint8List(16);
          if (ivSize > 0) {
            iv.setRange(0, ivSize, out, sc);
            sc += ivSize;
          } else if (constantIv.isNotEmpty) {
            final copyLen = constantIv.length > 16 ? 16 : constantIv.length;
            iv.setRange(0, copyLen, constantIv);
          }

          if (useSubsamples) {
            if (sc + 2 > sencEnd) break;
            final subCount = _u16(out, sc);
            sc += 2;
            final counter = Uint8List.fromList(iv);
            var ctrBlockPos = 16;
            final keystream = Uint8List(16);

            for (var sub = 0; sub < subCount; sub++) {
              if (sc + 6 > sencEnd) break;
              final clearBytes = _u16(out, sc);
              final encBytes = _u32(out, sc + 2);
              sc += 6;

              sampleCursor += clearBytes;
              if (sampleCursor + encBytes > nextMdat.end) break;

              if (encBytes > 0) {
                if (scheme == 'cbcs') {
                  _decryptCbcsPattern(
                    aes,
                    iv,
                    out,
                    sampleCursor,
                    encBytes,
                    cryptBlocks,
                    skipBlocks,
                  );
                } else {
                  ctrBlockPos = _decryptCtrInPlace(
                    aes,
                    counter,
                    keystream,
                    ctrBlockPos,
                    out,
                    sampleCursor,
                    encBytes,
                  );
                }
                sampleCursor += encBytes;
              }
            }
          } else {
            final sSize = i < sampleSizes.length ? sampleSizes[i] : defaultSampleSize;
            if (sSize <= 0 || sampleCursor + sSize > nextMdat.end) break;
            if (scheme == 'cbcs') {
              _decryptCbcsPattern(aes, iv, out, sampleCursor, sSize, cryptBlocks, skipBlocks);
            } else {
              final counter = Uint8List.fromList(iv);
              final keystream = Uint8List(16);
              _decryptCtrInPlace(aes, counter, keystream, 16, out, sampleCursor, sSize);
            }
            sampleCursor += sSize;
          }
        }

        for (final tb in trafKids) {
          if (tb.type == 'senc' ||
              tb.type == 'saio' ||
              tb.type == 'saiz' ||
              (tb == sencBox && sencIsPiff)) {
            out.setRange(tb.offset + 4, tb.offset + 8, const [0x66, 0x72, 0x65, 0x65]);
          }
        }
      }
    }

    return out;
  }

  static int _decryptCtrInPlace(
    _Aes128 aes,
    Uint8List counter,
    Uint8List keystream,
    int blockOffset,
    Uint8List buf,
    int start,
    int length,
  ) {
    var bOff = blockOffset;
    for (var i = 0; i < length; i++) {
      if (bOff >= 16) {
        aes.encryptBlock(counter, keystream);
        _incrementBe128(counter);
        bOff = 0;
      }
      buf[start + i] ^= keystream[bOff++];
    }
    return bOff;
  }

  static void _incrementBe128(Uint8List counter) {
    for (var i = 15; i >= 0; i--) {
      final v = (counter[i] + 1) & 0xFF;
      counter[i] = v;
      if (v != 0) break;
    }
  }

  static void _decryptCbcsPattern(
    _Aes128 aes,
    Uint8List iv,
    Uint8List buf,
    int start,
    int length,
    int cryptBlocks,
    int skipBlocks,
  ) {
    final fullBlocks = length ~/ 16;
    if (fullBlocks == 0) return;

    final prevCipher = Uint8List.fromList(iv);
    final curCipher = Uint8List(16);
    final plain = Uint8List(16);
    final hasPattern = cryptBlocks > 0 && skipBlocks > 0;
    final patternLen = cryptBlocks + skipBlocks;

    for (var blk = 0; blk < fullBlocks; blk++) {
      final pos = start + blk * 16;
      final isEncrypted = !hasPattern || (blk % patternLen) < cryptBlocks;
      if (!isEncrypted) continue;

      curCipher.setRange(0, 16, buf, pos);
      aes.decryptBlock(curCipher, plain);
      for (var k = 0; k < 16; k++) {
        buf[pos + k] = plain[k] ^ prevCipher[k];
      }
      prevCipher.setRange(0, 16, curCipher);
    }
  }
}

class _Aes128 {
  static const List<int> _sbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _invSbox = [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
  ];

  static const List<int> _rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

  final Uint8List _rk = Uint8List(176);
  final Uint8List _s = Uint8List(16);

  _Aes128(Uint8List key) {
    _rk.setRange(0, 16, key);
    for (var round = 0; round < 10; round++) {
      final prev = round * 16;
      final next = (round + 1) * 16;
      _rk[next] = _rk[prev] ^ _sbox[_rk[prev + 13]] ^ _rcon[round];
      _rk[next + 1] = _rk[prev + 1] ^ _sbox[_rk[prev + 14]];
      _rk[next + 2] = _rk[prev + 2] ^ _sbox[_rk[prev + 15]];
      _rk[next + 3] = _rk[prev + 3] ^ _sbox[_rk[prev + 12]];
      for (var j = 4; j < 16; j++) {
        _rk[next + j] = _rk[prev + j] ^ _rk[next + j - 4];
      }
    }
  }

  static int _xt(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xFF;

  static int _mul(int a, int b) {
    var r = 0;
    var x = a;
    var y = b;
    for (var i = 0; i < 8; i++) {
      if ((y & 1) != 0) r ^= x;
      x = _xt(x);
      y >>= 1;
    }
    return r;
  }

  void encryptBlock(Uint8List input, Uint8List output) {
    for (var i = 0; i < 16; i++) {
      _s[i] = input[i] ^ _rk[i];
    }

    for (var round = 1; round <= 10; round++) {
      for (var i = 0; i < 16; i++) {
        _s[i] = _sbox[_s[i]];
      }
      var t = _s[1]; _s[1] = _s[5]; _s[5] = _s[9]; _s[9] = _s[13]; _s[13] = t;
      t = _s[2]; _s[2] = _s[10]; _s[10] = t;
      t = _s[6]; _s[6] = _s[14]; _s[14] = t;
      t = _s[15]; _s[15] = _s[11]; _s[11] = _s[7]; _s[7] = _s[3]; _s[3] = t;

      if (round < 10) {
        for (var c = 0; c < 16; c += 4) {
          final a0 = _s[c], a1 = _s[c + 1], a2 = _s[c + 2], a3 = _s[c + 3];
          final u = a0 ^ a1 ^ a2 ^ a3;
          _s[c] = a0 ^ u ^ _xt(a0 ^ a1);
          _s[c + 1] = a1 ^ u ^ _xt(a1 ^ a2);
          _s[c + 2] = a2 ^ u ^ _xt(a2 ^ a3);
          _s[c + 3] = a3 ^ u ^ _xt(a3 ^ a0);
        }
      }

      final rOff = round * 16;
      for (var i = 0; i < 16; i++) {
        _s[i] ^= _rk[rOff + i];
      }
    }

    output.setRange(0, 16, _s);
  }

  void decryptBlock(Uint8List input, Uint8List output) {
    for (var i = 0; i < 16; i++) {
      _s[i] = input[i] ^ _rk[160 + i];
    }

    for (var round = 9; round >= 0; round--) {
      var t = _s[13]; _s[13] = _s[9]; _s[9] = _s[5]; _s[5] = _s[1]; _s[1] = t;
      t = _s[2]; _s[2] = _s[10]; _s[10] = t;
      t = _s[6]; _s[6] = _s[14]; _s[14] = t;
      t = _s[3]; _s[3] = _s[7]; _s[7] = _s[11]; _s[11] = _s[15]; _s[15] = t;

      for (var i = 0; i < 16; i++) {
        _s[i] = _invSbox[_s[i]];
      }

      final rOff = round * 16;
      for (var i = 0; i < 16; i++) {
        _s[i] ^= _rk[rOff + i];
      }

      if (round > 0) {
        for (var c = 0; c < 16; c += 4) {
          final a0 = _s[c], a1 = _s[c + 1], a2 = _s[c + 2], a3 = _s[c + 3];
          _s[c] = _mul(a0, 14) ^ _mul(a1, 11) ^ _mul(a2, 13) ^ _mul(a3, 9);
          _s[c + 1] = _mul(a0, 9) ^ _mul(a1, 14) ^ _mul(a2, 11) ^ _mul(a3, 13);
          _s[c + 2] = _mul(a0, 13) ^ _mul(a1, 9) ^ _mul(a2, 14) ^ _mul(a3, 11);
          _s[c + 3] = _mul(a0, 11) ^ _mul(a1, 13) ^ _mul(a2, 9) ^ _mul(a3, 14);
        }
      }
    }

    output.setRange(0, 16, _s);
  }
}
