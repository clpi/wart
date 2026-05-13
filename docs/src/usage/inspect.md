# Inspecting Modules

## Basic Inspection

```bash
wart inspect module.wasm
```

Output includes:
- Module type (core WASM or component)
- Number of types, functions, globals
- Imports and exports
- Start function

## Inspecting Components

For WebAssembly components:

```bash
wart inspect component.wasm
```

Shows:
- Interface types
- Functions
- Imports/exports
- Core modules

## Capabilities

View runtime capabilities:

```bash
wart inspect capabilities
```

## Output Formats

```bash
wart inspect capabilities --format json
wart inspect capabilities --format markdown
```

## Validation

By default, modules are validated. Skip with:

```bash
wart inspect --no-validate module.wasm
```
