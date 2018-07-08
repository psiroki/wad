import "dart:async";
import "dart:typed_data";

import "tables.dart";

int _getUint32(TypedData data) => data.buffer.asByteData().getUint32(0, Endianness.LITTLE_ENDIAN);

double _getFloat32(TypedData data) => data.buffer.asByteData().getFloat32(0, Endianness.LITTLE_ENDIAN);

double _getFloat64(TypedData data) => data.buffer.asByteData().getFloat64(0, Endianness.LITTLE_ENDIAN);

class StreamReader {
  StreamReader(this.source) : sourceIterator = new StreamIterator(source);

  bool get isAtEnd => _finished;

  int get bytesRead => _bytesRead;

  FutureOr<int> readByte() {
    if (_finished) return null;
    if (_lastResult == null || _lastResultPos >= _lastResult.length) {
      return sourceIterator.moveNext().then((bool available) {
        if (!available) {
          _finished = true;
          return null;
        }
        ++_bytesRead;
        _lastResult = sourceIterator.current;
        _lastResultPos = 1;
        return _lastResult.first;
      });
    }
    ++_bytesRead;
    return _lastResult[_lastResultPos++];
  }

  FutureOr<int> readVarUint(int maxBits) {
    return _readVarUint(maxBits, 0, 0);
  }

  FutureOr<int> readVarInt(int maxBits) {
    return _readVarUint(maxBits, 0, 0, signed: true);
  }

  FutureOr<int> _readVarUint(int maxBits, int valueSoFar, int bitsSoFar, {bool signed: false}) {
    while (bitsSoFar < maxBits) {
      FutureOr<int> byte = readByte();
      if (byte == null) return bitsSoFar > 0 ? _optApplySign(valueSoFar, bitsSoFar, signed: signed) : null;
      if (byte is Future) {
        return byte.then((int nextByte) {
          valueSoFar |= (nextByte & 0x7f) << bitsSoFar;
          bitsSoFar += 7;
          if (nextByte & 0x80 == 0 || bitsSoFar >= maxBits) return _optApplySign(valueSoFar, bitsSoFar, signed: signed);
          return _readVarUint(maxBits, valueSoFar, bitsSoFar, signed: signed);
        });
      } else {
        valueSoFar |= (byte & 0x7f) << bitsSoFar;
        bitsSoFar += 7;
        if (byte & 0x80 == 0) return _optApplySign(valueSoFar, bitsSoFar, signed: signed);
      }
    }
    return _optApplySign(valueSoFar, bitsSoFar, signed: signed);
  }

  int _optApplySign(int val, int numBits, {bool signed: false}) => signed ? _applySign(val, numBits) : val;

  int _applySign(int val, int numBits) {
    return val & (1 << numBits - 1) != 0 ? -((val ^ ((1 << numBits) - 1)) + 1) : val;
  }

  FutureOr<int> readUint32() {
    FutureOr<Uint8List> result = readBytes(4);
    if (result is Future) return result.then(_getUint32);
    return _getUint32(result);
  }

  FutureOr<double> readFloat32() {
    FutureOr<Uint8List> result = readBytes(4);
    if (result is Future) return result.then(_getFloat32);
    return _getFloat32(result);
  }

  FutureOr<double> readFloat64() {
    FutureOr<Uint8List> result = readBytes(8);
    if (result is Future) return result.then(_getFloat64);
    return _getFloat64(result);
  }

  FutureOr<Uint8List> readBytes(int numBytes) {
    if (_finished) return new Uint8List(0);
    return fillBuffer(new Uint8List(numBytes));
  }

  FutureOr<Uint8List> fillBuffer(Uint8List buffer) {
    return _fillBuffer(buffer, 0);
  }

  FutureOr<Uint8List> _fillBuffer(Uint8List buffer, int bufferPos) {
    if (_finished) return new Uint8List.view(buffer.buffer, buffer.offsetInBytes, bufferPos);
    if (_lastResult != null && _lastResultPos < _lastResult.length) {
      int end = bufferPos + _lastResult.length - _lastResultPos;
      if (end > buffer.length) end = buffer.length;
      buffer.setRange(bufferPos, end, _lastResult, _lastResultPos);
      int length = end - bufferPos;
      _lastResultPos += length;
      _bytesRead += length;
      bufferPos = end;
      if (bufferPos >= buffer.length) return buffer;
    }
    return sourceIterator.moveNext().then((bool available) {
      if (!available) {
        _finished = true;
        return new Uint8List.view(buffer.buffer, buffer.offsetInBytes, bufferPos);
      }
      _lastResult = sourceIterator.current;
      _lastResultPos = 0;
      return _fillBuffer(buffer, bufferPos);
    });
  }

  final Stream<List<int>> source;
  final StreamIterator<List<int>> sourceIterator;
  List<int> _lastResult;
  int _lastResultPos = 0;
  bool _finished = false;
  int _bytesRead = 0;
}

class DumpHelper {
  DumpHelper(this.sink);

  void write(Object obj) {
    String s = obj.toString();
    int nl = s.lastIndexOf('\n');
    if (nl < 0) {
      _col += s.length;
    } else {
      _col = s.length - nl - 1;
    }
    sink.write(s);
  }

  void writeln([Object obj]) => write(obj == null ? "\n" : "$obj\n");

  void dumpBytes(List<int> bytes, {String linePrefix}) {
    // 00 61 73 6d 01 00 00 00  01 07 01 60 02 7f 7f 01  |.asm.......`....|
    if (_col > 0) writeln();
    for (int base = 0; base < bytes.length; base += 16) {
      if (linePrefix != null) write(linePrefix);
      _dumpSection(bytes, base);
      write("  ");
      _dumpSection(bytes, base + 8);
      write("  |");
      int end = base + 16;
      if (end > bytes.length) end = bytes.length;
      write(new String.fromCharCodes(bytes.sublist(base, end).map((i) => i >= 32 && i < 127 ? i : 46)));
      write("|\n");
    }
  }

  void _dumpSection(List<int> bytes, int start) {
    if (start > bytes.length) start = bytes.length;
    int end = start + 8;
    if (end > bytes.length) end = bytes.length;
    if (end > start) write(bytes.sublist(start, end).map((i) => i.toRadixString(16).padLeft(2, '0')).join(" "));
    if (end - start < 8) {
      if (start < bytes.length) write(" ");
      write(new Iterable.generate(8 - (end - start), (_) => "  ").join(" "));
    }
  }

  final StringSink sink;
  int _col = 0;
}

class Indent {
  Indent(this.thisIndent, [String nextIndent]) : nextIndent = nextIndent ?? thisIndent;

  final String thisIndent;
  final String nextIndent;
}

Indent indentForOp(int opcode, String currentIndent, {int indentDepth: 2}) {
  switch (opcode) {
    case 0x02:  // block
    case 0x03:  // loop
    case 0x04:  // if
      return new Indent(currentIndent, "".padLeft(currentIndent.length + indentDepth));
    case 0x05:  // else
      return new Indent(currentIndent.substring(indentDepth), currentIndent);
    case 0x0b:  // end
      return new Indent(currentIndent.substring(indentDepth));
  }
  return null;
}

String typeToString(int typeId) {
  return knownTypes[typeId] ?? "unknown type with id 0x${typeId.toRadixString(16).padLeft(2, '0')}";
}

String externalKindToString(int kindId) {
  return knownExternalKinds[kindId] ?? "unknown external kind with id 0x${kindId.toRadixString(16).padLeft(2, '0')}";
}
