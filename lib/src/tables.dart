import "dart:async";

import "io.dart";

abstract class WasmType {
  const WasmType();

  FutureOr<String> readAndFormat(StreamReader reader);
}

class BlockType extends WasmType {
  const BlockType();

  FutureOr<String> readAndFormat(StreamReader reader) {
    FutureOr<int> type = reader.readVarUint(7);
    if (type is Future) type.then(_typeToString);
    return _typeToString(type);
  }

  String _typeToString(int type) {
    if (type == 0x40) return null;
    return typeToString(type);
  }

  @override
  String toString() => "block_type";
}

class BrTableType extends WasmType {
  const BrTableType();

  FutureOr<String> readAndFormat(StreamReader reader) async {
    int count = await reader.readVarUint(32);
    List<int> blockIndices = [];
    for (int i = 0; i < count; ++i) blockIndices.add(await reader.readVarUint(32));
    int defaultBlock = await reader.readVarUint(32);
    return "$blockIndices default: $defaultBlock";
  }

  @override
  String toString() => "br_table";
}

class MemoryImmediateType extends WasmType {
  const MemoryImmediateType();

  FutureOr<String> readAndFormat(StreamReader reader) async {
    int flagsAndAlignment = await reader.readVarUint(32);
    int offset = await reader.readVarUint(32);
    if (flagsAndAlignment == 0) return "offset: $offset";
    return "offset: $offset align:$flagsAndAlignment";
  }

  @override
  String toString() => "memory_immediate";
}

class VarIntType extends WasmType {
  const VarIntType(this.maxBits, {this.signed: true});

  FutureOr<String> readAndFormat(StreamReader reader) {
    FutureOr<int> val = signed ? reader.readVarInt(maxBits) : reader.readVarUint(maxBits);
    if (val is Future) return val.then((int val) => val.toString());
    return val.toString();
  }

  @override
  String toString() => "var${signed ? 'Int' : 'Uint'}$maxBits";

  final int maxBits;
  final bool signed;
}

class FloatType extends WasmType {
  const FloatType(this.numBits);

  FutureOr<String> readAndFormat(StreamReader reader) {
    FutureOr<double> val = numBits == 32 ? reader.readFloat32() : reader.readFloat64();
    if (val is Future) return val.then((double val) => val.toString());
    return val.toString();
  }

  @override
  String toString() => "float$numBits";

  final int numBits;
}

class Immediate {
  const Immediate(this.name, this.type);

  FutureOr<String> readAndFormat(StreamReader reader) {
    FutureOr<String> value = type.readAndFormat(reader);
    if (value == null) return null;
    if (value is Future) return value.then(_formatWithValueString);
    return _formatWithValueString(value);
  }

  @override
  String toString() => "${name ?? ''}: $type";

  String _formatWithValueString(String value) {
    if (name == null) return value;
    return "$name: $value";
  }

  final String name;
  final WasmType type;
}

class Opcode {
  const Opcode(this.code, this.immediates, this.mnemonic, this.docs);

  FutureOr<String> readImmediatesAndFormat(StreamReader reader, {int indent: 0}) async {
    StringBuffer sb = new StringBuffer(mnemonic);
    for (Immediate im in immediates) {
      String s = await im.readAndFormat(reader);
      if (s != null) sb..write(" ")..write(s);
    }
    if (docs?.isNotEmpty ?? false) {
      if (sb.length < 80 - indent) {
        sb.write("".padLeft(80 - indent - sb.length));
        sb.write("# $docs");
        return sb.toString();
      } else {
        String padding = "".padLeft(80 - indent);
        return "$padding# $docs\n$sb";
      }
    }
    return sb.toString();
  }

  final int code;
  final List<Immediate> immediates;
  final String mnemonic;
  final String docs;
}

const int exportSectionId = 7;
const int codeSectionId = 10;

const Map<int, String> knownTypes = const {
  0x7f: "i32",
  0x7e: "i64",
  0x7d: "f32",
  0x7c: "f64",
  0x70: "anyfunc",
  0x60: "func",
  0x40: "pseudo type for representing an empty block_type",
};

const Map<int, String> knownSectionIds = const {
  1: "Type (function signature declarations)",
  2: "Import (import declarations)",
  3: "Function (function declarations)",
  4: "Table (indirect function table and other tables)",
  5: "Memory (memory attributes)",
  6: "Global (global declarations)",
  exportSectionId: "Export (exports)",
  8: "Start (start function declaration)",
  9: "Element (elements section)",
  codeSectionId: "Code (function bodies (code))",
  11: "Data (data segments)",
};

const Map<int, String> knownExternalKinds = const {
  0: "Function",
  1: "Table",
  2: "Memory",
  3: "Global",
};

const Map<int, Opcode> knownOpcodes = const {
  0x00: const Opcode(0x00, const [], "unreachable", "trap immediately"),
  0x01: const Opcode(0x01, const [], "nop", "no operation"),
  0x02: const Opcode(0x02, const [const Immediate("sig", const BlockType())], "block", "begin a sequence of expressions, yielding 0 or 1 values"),
  0x03: const Opcode(0x03, const [const Immediate("sig", const BlockType())], "loop", "begin a block which can also form control flow loops"),
  0x04: const Opcode(0x04, const [const Immediate("sig", const BlockType())], "if", "begin if expression"),
  0x05: const Opcode(0x05, const [], "else", "begin else expression of if"),
  0x0b: const Opcode(0x0b, const [], "end", "end a block, loop, or if"),
  0x0c: const Opcode(0x0c, const [const Immediate("relative_depth", const VarIntType(32, signed: true))], "br", "break that targets an outer nested block"),
  0x0d: const Opcode(0x0d, const [const Immediate("relative_depth", const VarIntType(32, signed: true))], "br_if", "conditional break that targets an outer nested block"),
  0x0e: const Opcode(0x0e, const [const BrTableType()], "br_table", "branch table control flow construct"),
  0x0f: const Opcode(0x0f, const [], "return", "return zero or one value from this function"),
  0x10: const Opcode(0x10, const [const Immediate("function_index", const VarIntType(32, signed: true))], "call", "call a function by its index"),
  0x11: const Opcode(0x11, const [const Immediate("type_index", const VarIntType(32, signed: true)), const Immediate("reserved", const VarIntType(1, signed: true))], "call_indirect", "call a function indirect with an expected signature"),
  0x1a: const Opcode(0x1a, const [], "drop", "ignore value"),
  0x1b: const Opcode(0x1b, const [], "select", "select one of two values based on condition"),
  0x20: const Opcode(0x20, const [const Immediate("local_index", const VarIntType(32, signed: true))], "get_local", "read a local variable or parameter"),
  0x21: const Opcode(0x21, const [const Immediate("local_index", const VarIntType(32, signed: true))], "set_local", "write a local variable or parameter"),
  0x22: const Opcode(0x22, const [const Immediate("local_index", const VarIntType(32, signed: true))], "tee_local", "write a local variable or parameter and return the same value"),
  0x23: const Opcode(0x23, const [const Immediate("global_index", const VarIntType(32, signed: true))], "get_global", "read a global variable"),
  0x24: const Opcode(0x24, const [const Immediate("global_index", const VarIntType(32, signed: true))], "set_global", "write a global variable"),
  0x28: const Opcode(0x28, const [const Immediate(null, const MemoryImmediateType())], "i32.load", "load from memory"),
  0x29: const Opcode(0x29, const [const Immediate(null, const MemoryImmediateType())], "i64.load", "load from memory"),
  0x2a: const Opcode(0x2a, const [const Immediate(null, const MemoryImmediateType())], "f32.load", "load from memory"),
  0x2b: const Opcode(0x2b, const [const Immediate(null, const MemoryImmediateType())], "f64.load", "load from memory"),
  0x2c: const Opcode(0x2c, const [const Immediate(null, const MemoryImmediateType())], "i32.load8_s", "load from memory"),
  0x2d: const Opcode(0x2d, const [const Immediate(null, const MemoryImmediateType())], "i32.load8_u", "load from memory"),
  0x2e: const Opcode(0x2e, const [const Immediate(null, const MemoryImmediateType())], "i32.load16_s", "load from memory"),
  0x2f: const Opcode(0x2f, const [const Immediate(null, const MemoryImmediateType())], "i32.load16_u", "load from memory"),
  0x30: const Opcode(0x30, const [const Immediate(null, const MemoryImmediateType())], "i64.load8_s", "load from memory"),
  0x31: const Opcode(0x31, const [const Immediate(null, const MemoryImmediateType())], "i64.load8_u", "load from memory"),
  0x32: const Opcode(0x32, const [const Immediate(null, const MemoryImmediateType())], "i64.load16_s", "load from memory"),
  0x33: const Opcode(0x33, const [const Immediate(null, const MemoryImmediateType())], "i64.load16_u", "load from memory"),
  0x34: const Opcode(0x34, const [const Immediate(null, const MemoryImmediateType())], "i64.load32_s", "load from memory"),
  0x35: const Opcode(0x35, const [const Immediate(null, const MemoryImmediateType())], "i64.load32_u", "load from memory"),
  0x36: const Opcode(0x36, const [const Immediate(null, const MemoryImmediateType())], "i32.store", "store to memory"),
  0x37: const Opcode(0x37, const [const Immediate(null, const MemoryImmediateType())], "i64.store", "store to memory"),
  0x38: const Opcode(0x38, const [const Immediate(null, const MemoryImmediateType())], "f32.store", "store to memory"),
  0x39: const Opcode(0x39, const [const Immediate(null, const MemoryImmediateType())], "f64.store", "store to memory"),
  0x3a: const Opcode(0x3a, const [const Immediate(null, const MemoryImmediateType())], "i32.store8", "store to memory"),
  0x3b: const Opcode(0x3b, const [const Immediate(null, const MemoryImmediateType())], "i32.store16", "store to memory"),
  0x3c: const Opcode(0x3c, const [const Immediate(null, const MemoryImmediateType())], "i64.store8", "store to memory"),
  0x3d: const Opcode(0x3d, const [const Immediate(null, const MemoryImmediateType())], "i64.store16", "store to memory"),
  0x3e: const Opcode(0x3e, const [const Immediate(null, const MemoryImmediateType())], "i64.store32", "store to memory"),
  0x3f: const Opcode(0x3f, const [const Immediate("reserved", const VarIntType(1, signed: true))], "current_memory", "query the size of memory"),
  0x40: const Opcode(0x40, const [const Immediate("reserved", const VarIntType(1, signed: true))], "grow_memory", "grow the size of memory"),
  0x41: const Opcode(0x41, const [const Immediate("value", const VarIntType(32, signed: false))], "i32.const", "a constant value interpreted as i32"),
  0x42: const Opcode(0x42, const [const Immediate("value", const VarIntType(64, signed: false))], "i64.const", "a constant value interpreted as i64"),
  0x43: const Opcode(0x43, const [const Immediate("value", const FloatType(32))], "f32.const", "a constant value interpreted as f32"),
  0x44: const Opcode(0x44, const [const Immediate("value", const FloatType(64))], "f64.const", "a constant value interpreted as f64"),
  0x45: const Opcode(0x45, const [], "i32.eqz", ""),
  0x46: const Opcode(0x46, const [], "i32.eq", ""),
  0x47: const Opcode(0x47, const [], "i32.ne", ""),
  0x48: const Opcode(0x48, const [], "i32.lt_s", ""),
  0x49: const Opcode(0x49, const [], "i32.lt_u", ""),
  0x4a: const Opcode(0x4a, const [], "i32.gt_s", ""),
  0x4b: const Opcode(0x4b, const [], "i32.gt_u", ""),
  0x4c: const Opcode(0x4c, const [], "i32.le_s", ""),
  0x4d: const Opcode(0x4d, const [], "i32.le_u", ""),
  0x4e: const Opcode(0x4e, const [], "i32.ge_s", ""),
  0x4f: const Opcode(0x4f, const [], "i32.ge_u", ""),
  0x50: const Opcode(0x50, const [], "i64.eqz", ""),
  0x51: const Opcode(0x51, const [], "i64.eq", ""),
  0x52: const Opcode(0x52, const [], "i64.ne", ""),
  0x53: const Opcode(0x53, const [], "i64.lt_s", ""),
  0x54: const Opcode(0x54, const [], "i64.lt_u", ""),
  0x55: const Opcode(0x55, const [], "i64.gt_s", ""),
  0x56: const Opcode(0x56, const [], "i64.gt_u", ""),
  0x57: const Opcode(0x57, const [], "i64.le_s", ""),
  0x58: const Opcode(0x58, const [], "i64.le_u", ""),
  0x59: const Opcode(0x59, const [], "i64.ge_s", ""),
  0x5a: const Opcode(0x5a, const [], "i64.ge_u", ""),
  0x5b: const Opcode(0x5b, const [], "f32.eq", ""),
  0x5c: const Opcode(0x5c, const [], "f32.ne", ""),
  0x5d: const Opcode(0x5d, const [], "f32.lt", ""),
  0x5e: const Opcode(0x5e, const [], "f32.gt", ""),
  0x5f: const Opcode(0x5f, const [], "f32.le", ""),
  0x60: const Opcode(0x60, const [], "f32.ge", ""),
  0x61: const Opcode(0x61, const [], "f64.eq", ""),
  0x62: const Opcode(0x62, const [], "f64.ne", ""),
  0x63: const Opcode(0x63, const [], "f64.lt", ""),
  0x64: const Opcode(0x64, const [], "f64.gt", ""),
  0x65: const Opcode(0x65, const [], "f64.le", ""),
  0x66: const Opcode(0x66, const [], "f64.ge", ""),
  0x67: const Opcode(0x67, const [], "i32.clz", ""),
  0x68: const Opcode(0x68, const [], "i32.ctz", ""),
  0x69: const Opcode(0x69, const [], "i32.popcnt", ""),
  0x6a: const Opcode(0x6a, const [], "i32.add", ""),
  0x6b: const Opcode(0x6b, const [], "i32.sub", ""),
  0x6c: const Opcode(0x6c, const [], "i32.mul", ""),
  0x6d: const Opcode(0x6d, const [], "i32.div_s", ""),
  0x6e: const Opcode(0x6e, const [], "i32.div_u", ""),
  0x6f: const Opcode(0x6f, const [], "i32.rem_s", ""),
  0x70: const Opcode(0x70, const [], "i32.rem_u", ""),
  0x71: const Opcode(0x71, const [], "i32.and", ""),
  0x72: const Opcode(0x72, const [], "i32.or", ""),
  0x73: const Opcode(0x73, const [], "i32.xor", ""),
  0x74: const Opcode(0x74, const [], "i32.shl", ""),
  0x75: const Opcode(0x75, const [], "i32.shr_s", ""),
  0x76: const Opcode(0x76, const [], "i32.shr_u", ""),
  0x77: const Opcode(0x77, const [], "i32.rotl", ""),
  0x78: const Opcode(0x78, const [], "i32.rotr", ""),
  0x79: const Opcode(0x79, const [], "i64.clz", ""),
  0x7a: const Opcode(0x7a, const [], "i64.ctz", ""),
  0x7b: const Opcode(0x7b, const [], "i64.popcnt", ""),
  0x7c: const Opcode(0x7c, const [], "i64.add", ""),
  0x7d: const Opcode(0x7d, const [], "i64.sub", ""),
  0x7e: const Opcode(0x7e, const [], "i64.mul", ""),
  0x7f: const Opcode(0x7f, const [], "i64.div_s", ""),
  0x80: const Opcode(0x80, const [], "i64.div_u", ""),
  0x81: const Opcode(0x81, const [], "i64.rem_s", ""),
  0x82: const Opcode(0x82, const [], "i64.rem_u", ""),
  0x83: const Opcode(0x83, const [], "i64.and", ""),
  0x84: const Opcode(0x84, const [], "i64.or", ""),
  0x85: const Opcode(0x85, const [], "i64.xor", ""),
  0x86: const Opcode(0x86, const [], "i64.shl", ""),
  0x87: const Opcode(0x87, const [], "i64.shr_s", ""),
  0x88: const Opcode(0x88, const [], "i64.shr_u", ""),
  0x89: const Opcode(0x89, const [], "i64.rotl", ""),
  0x8a: const Opcode(0x8a, const [], "i64.rotr", ""),
  0x8b: const Opcode(0x8b, const [], "f32.abs", ""),
  0x8c: const Opcode(0x8c, const [], "f32.neg", ""),
  0x8d: const Opcode(0x8d, const [], "f32.ceil", ""),
  0x8e: const Opcode(0x8e, const [], "f32.floor", ""),
  0x8f: const Opcode(0x8f, const [], "f32.trunc", ""),
  0x90: const Opcode(0x90, const [], "f32.nearest", ""),
  0x91: const Opcode(0x91, const [], "f32.sqrt", ""),
  0x92: const Opcode(0x92, const [], "f32.add", ""),
  0x93: const Opcode(0x93, const [], "f32.sub", ""),
  0x94: const Opcode(0x94, const [], "f32.mul", ""),
  0x95: const Opcode(0x95, const [], "f32.div", ""),
  0x96: const Opcode(0x96, const [], "f32.min", ""),
  0x97: const Opcode(0x97, const [], "f32.max", ""),
  0x98: const Opcode(0x98, const [], "f32.copysign", ""),
  0x99: const Opcode(0x99, const [], "f64.abs", ""),
  0x9a: const Opcode(0x9a, const [], "f64.neg", ""),
  0x9b: const Opcode(0x9b, const [], "f64.ceil", ""),
  0x9c: const Opcode(0x9c, const [], "f64.floor", ""),
  0x9d: const Opcode(0x9d, const [], "f64.trunc", ""),
  0x9e: const Opcode(0x9e, const [], "f64.nearest", ""),
  0x9f: const Opcode(0x9f, const [], "f64.sqrt", ""),
  0xa0: const Opcode(0xa0, const [], "f64.add", ""),
  0xa1: const Opcode(0xa1, const [], "f64.sub", ""),
  0xa2: const Opcode(0xa2, const [], "f64.mul", ""),
  0xa3: const Opcode(0xa3, const [], "f64.div", ""),
  0xa4: const Opcode(0xa4, const [], "f64.min", ""),
  0xa5: const Opcode(0xa5, const [], "f64.max", ""),
  0xa6: const Opcode(0xa6, const [], "f64.copysign", ""),
  0xa7: const Opcode(0xa7, const [], "i32.wrap/i64", ""),
  0xa8: const Opcode(0xa8, const [], "i32.trunc_s/f32", ""),
  0xa9: const Opcode(0xa9, const [], "i32.trunc_u/f32", ""),
  0xaa: const Opcode(0xaa, const [], "i32.trunc_s/f64", ""),
  0xab: const Opcode(0xab, const [], "i32.trunc_u/f64", ""),
  0xac: const Opcode(0xac, const [], "i64.extend_s/i32", ""),
  0xad: const Opcode(0xad, const [], "i64.extend_u/i32", ""),
  0xae: const Opcode(0xae, const [], "i64.trunc_s/f32", ""),
  0xaf: const Opcode(0xaf, const [], "i64.trunc_u/f32", ""),
  0xb0: const Opcode(0xb0, const [], "i64.trunc_s/f64", ""),
  0xb1: const Opcode(0xb1, const [], "i64.trunc_u/f64", ""),
  0xb2: const Opcode(0xb2, const [], "f32.convert_s/i32", ""),
  0xb3: const Opcode(0xb3, const [], "f32.convert_u/i32", ""),
  0xb4: const Opcode(0xb4, const [], "f32.convert_s/i64", ""),
  0xb5: const Opcode(0xb5, const [], "f32.convert_u/i64", ""),
  0xb6: const Opcode(0xb6, const [], "f32.demote/f64", ""),
  0xb7: const Opcode(0xb7, const [], "f64.convert_s/i32", ""),
  0xb8: const Opcode(0xb8, const [], "f64.convert_u/i32", ""),
  0xb9: const Opcode(0xb9, const [], "f64.convert_s/i64", ""),
  0xba: const Opcode(0xba, const [], "f64.convert_u/i64", ""),
  0xbb: const Opcode(0xbb, const [], "f64.promote/f32", ""),
  0xbc: const Opcode(0xbc, const [], "i32.reinterpret/f32", ""),
  0xbd: const Opcode(0xbd, const [], "i64.reinterpret/f64", ""),
  0xbe: const Opcode(0xbe, const [], "f32.reinterpret/i32", ""),
  0xbf: const Opcode(0xbf, const [], "f64.reinterpret/i64", ""),
};
