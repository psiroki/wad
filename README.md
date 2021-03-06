# WAD - WebAssembly Disassembler

## Usage

```
dart bin/wasm_dump.dart [path_to_wasm_file] [--rawCode] [--doNotParse]
```

- `path_to_wasm_file`: a path to a WASM binary file, the file will be read from stdin if missing
- `--rawCode`: do not disassemble, dump the bytecode instead
- `--doNotParse`: do not parse any sections, just dump the bytes themselves (kind of implies `--rawCode`)

## Example output

This is the dump of a simple WASM file with two functions: one returns the sum of the two parameters,
the second one is a factorial function. Some supported sections are parsed and the code is disassembled.

```
Magic:
00 61 73 6d                                       |.asm|
Version:
01 00 00 00                                       |....|


Section code: 0x01 Type (function signature declarations)
Section size: 0x0c

- Function type #0 (i32, i32) → (i32)
- Function type #1 (i32) → (i32)


Section code: 0x03 Function (function declarations)
Section size: 0x03

- Function #0 is of function type #0
- Function #1 is of function type #1


Section code: 0x05 Memory (memory attributes)
Section size: 0x03

01 00 02                                          |...|


Section code: 0x07 Export (exports)
Section size: 0x1c

- Export "add" of kind Function → entry #0
- Export "factorial" of kind Function → entry #1
- Export "memory" of kind Memory → entry #0


Section code: 0x0a Code (function bodies (code))
Section size: 0x2a

- Function #0

    get_local 0                           # read a local variable or parameter
    get_local 1                           # read a local variable or parameter
    i32.add
  end                                     # end a block, loop, or if

- Function #1
  Local #0: 1 of i32

    i32.const 1                           # a constant value interpreted as i32
    set_local 1                           # write a local variable or parameter
    loop                                  # begin a block which can also form control flow loops
      get_local 0                         # read a local variable or parameter
      get_local 1                         # read a local variable or parameter
      i32.mul
      set_local 1                         # write a local variable or parameter
      get_local 0                         # read a local variable or parameter
      i32.const 1                         # a constant value interpreted as i32
      i32.sub
      tee_local 0                         # write a local variable or parameter and return the same value
      i32.const 0                         # a constant value interpreted as i32
      i32.ne
      br_if 0                             # conditional break that targets an outer nested block
    end                                   # end a block, loop, or if
    get_local 1                           # read a local variable or parameter
  end                                     # end a block, loop, or if



Section code: 0x00
Section size: 0x14
Custom section: "name"

02 0d 02 00 02 00 00 01  00 01 02 00 00 01 00     |...............|
```
