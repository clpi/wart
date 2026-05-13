# Shell Mode

## Starting the Shell

```bash
wart shell
wart repl
wart sh
```

Or load a module on startup:

```bash
wart shell module.wasm
wart repl module.wat
wart sh module.c
```

## Commands

| Command | Description |
|---------|-------------|
| `:help` | Show available commands |
| `:load <file>` | Load `.wasm`, `.wat`, `.c`, or `.cpp` into the session |
| `:exports` | List exports with signatures |
| `:run [fn args...]` | Run default entry, or run a specific function |
| `:call <name> [args...]` | Call an exported function |
| `:lang auto|wat|c|cpp|wasm` | Force or reset language detection |
| `:paste` + `:end` | Multi-line input mode |
| `:history` | Show command/input history |
| `:quit` / `:exit` | Exit the shell |
| `!!` | Re-run previous input |
| `!<cmd>` | Run a host shell command |

## Example Session

```
$ wart shell examples/simple.wasm
Loading examples/simple.wasm...
Loaded module from examples/simple.wasm (wasm -> wasm)

Exports:
  fn _start()
  memory memory

Type :help for commands, :quit to exit.

wart*> :exports
Exports
  fn _start()
  memory memory

wart*> :run
Running entry: _start
[module output]

wart*> :exit
Goodbye!
```

## Debug Mode

Enable debug output in shell:

```bash
wart --debug shell module.wasm
```
