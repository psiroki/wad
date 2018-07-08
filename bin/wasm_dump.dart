import "dart:async";
import "dart:io";

import "package:wad/wad.dart";

Future<Null> main(List<String> args) async {
  args = args.toList();
  bool disassemble = true;
  bool doNotParse = false;
  for (int i = args.length - 1; i >= 0; --i) {
    int remove = 0;
    switch (args[i]) {
      case "--rawCode":
        disassemble = false;
        remove = 1;
        break;
      case "--doNotParse":
        doNotParse = true;
        remove = 1;
        break;
    }
    if (remove > 0) args.removeRange(i, i + remove);
  }
  Stream<List<int>> input = stdin;
  if (args.isNotEmpty) input = new File(args.last).openRead();
  await new WasmDump(input, stdout, disassemble: disassemble, doNotParse: doNotParse).dump();
}
