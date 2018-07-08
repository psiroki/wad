# WAD - WebAssembly Disassembler

## Usage

```dart bin/wasm_dump.dart [path_to_wasm_file] [--rawCode] [--doNotParse]```

- `path_to_wasm_file`: a path to a WASM binary file, the file will be read from stdin if missing
- `--rawCode`: do not disassemble, dump the bytecode instead
- `--doNotParse`: do not parse known sections, just dump the bytes themselves (kind of implies `--rawCode`)
