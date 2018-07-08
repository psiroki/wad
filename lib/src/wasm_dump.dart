import "dart:async";
import "dart:convert";

import "io.dart";
import "tables.dart";

class WasmDump {
  WasmDump(Stream<List<int>> input, StringSink output, {this.disassemble: true, this.doNotParse: false}) :
    reader = new StreamReader(input),
    out = new DumpHelper(output);

  Future<Null> dump() async {
    out.writeln("Magic:");
    out.dumpBytes(await reader.readBytes(4));
    out.writeln("Version:");
    out.dumpBytes(await reader.readBytes(4));
    while (!reader.isAtEnd) {
      int sectionId = await reader.readByte();
      if (sectionId == null) break;
      out.write("\n\nSection code: 0x${sectionId.toRadixString(16).padLeft(2, '0')}");
      String name = knownSectionIds[sectionId];
      if (name != null) out..write(" ")..write(name);
      out.writeln();
      int sectionSize = await reader.readVarUint(32);
      out.writeln("Section size: 0x${sectionSize.toRadixString(16).padLeft(2, '0')}");
      int end = reader.bytesRead + sectionSize;
      if (sectionId == 0) {
        int nameLength = await reader.readVarUint(32);
        out.writeln("Custom section: ${JSON.encode(UTF8.decode(await reader.readBytes(nameLength)))}");
      }
      int length = end - reader.bytesRead;
      out.writeln();
      bool dump = false;
      if (!doNotParse) {
        switch (sectionId) {
          case codeSectionId:
            await _dumpCodeSection();
            break;
          case exportSectionId:
            await _dumpExportSection();
            break;
          default:
            dump = true;
        }
      }
      if (dump) out.dumpBytes(await reader.readBytes(length));
    }
  }
  Future<Null> _dumpCodeSection() async {
    int count = await reader.readVarUint(32);
    for (int i = 0; i < count; ++i) {
      int size = await reader.readVarUint(32);
      int end = reader.bytesRead + size;
      out.writeln("- Function #$i");
      int numLocals = await reader.readVarUint(32);
      for (int j = 0; j < numLocals; ++j) {
        int count = await reader.readVarUint(32);
        int type = await reader.readByte();
        out.writeln("  Local #$j: $count of ${typeToString(type)}");
      }
      int codeBytes = end - reader.bytesRead;
      out.writeln();
      if (disassemble) {
        String prefix = "".padLeft(4);
        bool failed = false;
        while (reader.bytesRead < end) {
          int b = await reader.readByte();
          if (b == null) break;
          Opcode op = knownOpcodes[b];
          if (op == null) {
            failed = true;
            break;
          }
          String thisPrefix = prefix;
          Indent indent = indentForOp(b, prefix, indentDepth: 2);
          if (indent != null) {
            thisPrefix = indent.thisIndent;
            prefix = indent.nextIndent;
          }
          String line = await op.readImmediatesAndFormat(reader, indent: thisPrefix.length);
          out.writeln("$thisPrefix$line");
        }
        if (failed && reader.bytesRead < end) {
          out.dumpBytes(await reader.readBytes(end - reader.bytesRead), linePrefix: "    ");
        }
      } else {
        out.dumpBytes(await reader.readBytes(codeBytes), linePrefix: "    ");
      }
      out.writeln();
    }
  }

  Future<Null> _dumpExportSection() async {
    int count = await reader.readVarUint(32);
    for (int i = 0; i < count; ++i) {
      int nameLength = await reader.readVarUint(32);
      String name = UTF8.decode(await reader.readBytes(nameLength));
      // external kind comes here
      int kind = await reader.readByte();
      int index = await reader.readVarUint(32);
      out.writeln("- Export ${JSON.encode(name)} of kind ${externalKindToString(kind)} \u2192 entry #$index");
    }
  }

  final StreamReader reader;
  final DumpHelper out;
  final bool disassemble;
  final bool doNotParse;
}
