# Nushell completion for wart

export extern "wart" [
    --help(-h)              # Show help
    --version(-v)           # Show version
    --debug(-d)             # Enable debug output
    --jit(-j)               # Enable JIT compilation
    --aot(-a)               # Enable AOT compilation
    --wat(-w)               # Force WAT parsing
    --wast                  # Force WAST parsing
    --function(-f): string  # Specify function to execute
    --output(-o): string    # Output file for AOT
    --cfile(-c): string     # Compile C source to WASM
    --cppfile(-C): string   # Compile C++ source to WASM
    --no-validate           # Skip WASM validation
    --color                 # Enable colored output
    --no-color              # Disable colored output
    --verbose(-V): int      # Set verbosity level
]

export extern "wart run" [
    file: string            # WASM/WAT file to execute
    ...args: string         # Arguments to pass to the module
    --debug(-d)             # Enable debug output
    --jit(-j)               # Enable JIT compilation
    --aot(-a)               # Enable AOT compilation
    --wat(-w)               # Force WAT parsing
    --function(-f): string  # Specify function to execute
    --no-validate           # Skip WASM validation
    --color                 # Enable colored output
    --no-color              # Disable colored output
    --verbose(-V): int      # Set verbosity level
]

export extern "wart compile" [
    file: string            # WASM file to compile
    --output(-o): string    # Output file path
    --aot(-a)               # Enable AOT compilation
    --no-validate           # Skip WASM validation
]

export extern "wart init" [
    --name(-n): string      # Project name
    --template(-t): string  # Project template
]

def "nu-complete wart package actions" [] {
    ["list", "add", "remove", "create", "info"]
}

export extern "wart package" [
    action?: string@"nu-complete wart package actions"  # Package action
    name?: string           # Package name
    path?: string           # Package path
]

export extern "wart pkg" [
    action?: string@"nu-complete wart package actions"  # Package action
    name?: string           # Package name
    path?: string           # Package path
]

export extern "wart workspace" [
    action?: string@"nu-complete wart package actions"  # Package action
    name?: string           # Package name
    path?: string           # Package path
]

export extern "wart ws" [
    action?: string@"nu-complete wart package actions"  # Package action
    name?: string           # Package name
    path?: string           # Package path
]

export extern "wart build" [
    --output(-o): string    # Output file path
    --source(-s)            # Include source files
    --workspace(-w)         # Package all workspace members
]

export extern "wart pack" [
    --output(-o): string    # Output file path
    --source(-s)            # Include source files
    --workspace(-w)         # Package all workspace members
]

def "nu-complete wart access levels" [] {
    ["public", "private", "restricted"]
}

export extern "wart deploy" [
    package_path?: string                           # Package path to deploy
    --registry(-r): string                          # Registry to deploy to
    --dry-run(-n)                                   # Dry run
    --access(-a): string@"nu-complete wart access levels"  # Access level
]

export extern "wart publish" [
    package_path?: string                           # Package path to deploy
    --registry(-r): string                          # Registry to deploy to
    --dry-run(-n)                                   # Dry run
    --access(-a): string@"nu-complete wart access levels"  # Access level
]

export extern "wart pub" [
    package_path?: string                           # Package path to deploy
    --registry(-r): string                          # Registry to deploy to
    --dry-run(-n)                                   # Dry run
    --access(-a): string@"nu-complete wart access levels"  # Access level
]

export extern "wart bench" [
    file?: string           # WASM file to benchmark
    --debug(-d)             # Enable debug output
    --jit(-j)               # Enable JIT compilation
    --no-validate           # Skip WASM validation
    --color                 # Enable colored output
    --no-color              # Disable colored output
    --verbose(-V): int      # Set verbosity level
]

export extern "wart inspect" [
    file: string            # WASM file to inspect
    --color                 # Enable colored output
    --no-color              # Disable colored output
]

def "nu-complete wart config actions" [] {
    ["init", "list", "get", "set", "reset"]
}

export extern "wart config" [
    action: string@"nu-complete wart config actions"  # Config action
    key?: string            # Configuration key
    value?: string          # Configuration value
]

def "nu-complete wart shells" [] {
    ["bash", "zsh", "fish", "powershell", "elvish", "nu", "xonsh", "tcsh"]
}

export extern "wart completion" [
    shell?: string@"nu-complete wart shells"  # Shell to generate completions for
]

export extern "wart help" []
export extern "wart version" []

export extern "wart shell" [
    file?: string           # WASM file to load in shell
]

export extern "wart repl" [
    file?: string           # WASM file to load in shell
]

export extern "wart sh" [
    file?: string           # WASM file to load in shell
]
