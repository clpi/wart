# Fish completion for wart

# Commands
complete -c wart -f -n __fish_use_subcommand -a run -d "Execute a WebAssembly module"
complete -c wart -f -n __fish_use_subcommand -a compile -d "Compile WASM to native executable"
complete -c wart -f -n __fish_use_subcommand -a init -d "Initialize a new wart project"
complete -c wart -f -n __fish_use_subcommand -a package -d "Manage packages"
complete -c wart -f -n __fish_use_subcommand -a pkg -d "Manage packages (alias)"
complete -c wart -f -n __fish_use_subcommand -a workspace -d "Manage packages (alias)"
complete -c wart -f -n __fish_use_subcommand -a ws -d "Manage packages (alias)"
complete -c wart -f -n __fish_use_subcommand -a build -d "Create a distributable package"
complete -c wart -f -n __fish_use_subcommand -a pack -d "Create a distributable package (alias)"
complete -c wart -f -n __fish_use_subcommand -a deploy -d "Deploy package to registry"
complete -c wart -f -n __fish_use_subcommand -a publish -d "Deploy package to registry (alias)"
complete -c wart -f -n __fish_use_subcommand -a pub -d "Deploy package to registry (alias)"
complete -c wart -f -n __fish_use_subcommand -a bench -d "Run benchmark suite"
complete -c wart -f -n __fish_use_subcommand -a inspect -d "Inspect a WebAssembly module"
complete -c wart -f -n __fish_use_subcommand -a config -d "Manage configuration"
complete -c wart -f -n __fish_use_subcommand -a completion -d "Generate completions"
complete -c wart -f -n __fish_use_subcommand -a help -d "Show help"
complete -c wart -f -n __fish_use_subcommand -a version -d "Show version"
complete -c wart -f -n __fish_use_subcommand -a shell -d "Interactive WASM shell"
complete -c wart -f -n __fish_use_subcommand -a repl -d "Interactive WASM shell (alias)"
complete -c wart -f -n __fish_use_subcommand -a sh -d "Interactive WASM shell (alias)"

# run/inspect/compile options
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l debug -d "Enable debug output"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s d -d "Enable debug output"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l jit -d "Enable JIT compilation"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s j -d "Enable JIT compilation"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l aot -d "Enable AOT compilation"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s a -d "Enable AOT compilation"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l wat -d "Force WAT parsing"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s w -d "Force WAT parsing"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l wast -d "Force WAST parsing"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l function -d "Specify function to execute" -r
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s f -d "Specify function to execute" -r
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l output -d "Output file for AOT" -r -F
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s o -d "Output file for AOT" -r -F
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l cfile -d "Compile C source to WASM" -r -F
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s c -d "Compile C source to WASM" -r -F
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l cppfile -d "Compile C++ source to WASM" -r -F
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s C -d "Compile C++ source to WASM" -r -F
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l no-validate -d "Skip WASM validation"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l color -d "Enable colored output"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l no-color -d "Disable colored output"
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -l verbose -d "Set verbosity level" -r
complete -c wart -n "__fish_seen_subcommand_from run inspect compile" -s V -d "Set verbosity level" -r

# bench options
complete -c wart -n "__fish_seen_subcommand_from bench" -l debug -d "Enable debug output"
complete -c wart -n "__fish_seen_subcommand_from bench" -s d -d "Enable debug output"
complete -c wart -n "__fish_seen_subcommand_from bench" -l jit -d "Enable JIT compilation"
complete -c wart -n "__fish_seen_subcommand_from bench" -s j -d "Enable JIT compilation"
complete -c wart -n "__fish_seen_subcommand_from bench" -l no-validate -d "Skip WASM validation"
complete -c wart -n "__fish_seen_subcommand_from bench" -l color -d "Enable colored output"
complete -c wart -n "__fish_seen_subcommand_from bench" -l no-color -d "Disable colored output"
complete -c wart -n "__fish_seen_subcommand_from bench" -l verbose -d "Set verbosity level" -r

# package/workspace actions
complete -c wart -n "__fish_seen_subcommand_from package pkg workspace ws" -f -a "list" -d "List packages"
complete -c wart -n "__fish_seen_subcommand_from package pkg workspace ws" -f -a "add" -d "Add a package"
complete -c wart -n "__fish_seen_subcommand_from package pkg workspace ws" -f -a "remove" -d "Remove a package"
complete -c wart -n "__fish_seen_subcommand_from package pkg workspace ws" -f -a "create" -d "Create a new package"
complete -c wart -n "__fish_seen_subcommand_from package pkg workspace ws" -f -a "info" -d "Show package info"

# build/pack options
complete -c wart -n "__fish_seen_subcommand_from build pack" -l output -d "Output file path" -r -F
complete -c wart -n "__fish_seen_subcommand_from build pack" -s o -d "Output file path" -r -F
complete -c wart -n "__fish_seen_subcommand_from build pack" -l source -d "Include source files"
complete -c wart -n "__fish_seen_subcommand_from build pack" -s s -d "Include source files"
complete -c wart -n "__fish_seen_subcommand_from build pack" -l workspace -d "Package all workspace members"
complete -c wart -n "__fish_seen_subcommand_from build pack" -s w -d "Package all workspace members"

# deploy/publish options
complete -c wart -n "__fish_seen_subcommand_from deploy publish pub" -l registry -d "Registry to deploy to" -r
complete -c wart -n "__fish_seen_subcommand_from deploy publish pub" -s r -d "Registry to deploy to" -r
complete -c wart -n "__fish_seen_subcommand_from deploy publish pub" -l dry-run -d "Dry run"
complete -c wart -n "__fish_seen_subcommand_from deploy publish pub" -s n -d "Dry run"
complete -c wart -n "__fish_seen_subcommand_from deploy publish pub" -l access -d "Access level" -r -f -a "public private restricted"
complete -c wart -n "__fish_seen_subcommand_from deploy publish pub" -s a -d "Access level" -r -f -a "public private restricted"

# config actions
complete -c wart -n "__fish_seen_subcommand_from config" -f -a "init" -d "Initialize configuration"
complete -c wart -n "__fish_seen_subcommand_from config" -f -a "list" -d "List all configuration"
complete -c wart -n "__fish_seen_subcommand_from config" -f -a "get" -d "Get configuration value"
complete -c wart -n "__fish_seen_subcommand_from config" -f -a "set" -d "Set configuration value"
complete -c wart -n "__fish_seen_subcommand_from config" -f -a "reset" -d "Reset configuration"

# completion shells
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "bash" -d "Bash shell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "zsh" -d "Zsh shell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "fish" -d "Fish shell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "powershell" -d "PowerShell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "elvish" -d "Elvish shell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "nu" -d "Nushell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "xonsh" -d "Xonsh shell"
complete -c wart -n "__fish_seen_subcommand_from completion" -f -a "tcsh" -d "Tcsh shell"

# init options
complete -c wart -n "__fish_seen_subcommand_from init" -l template -d "Project template" -r
complete -c wart -n "__fish_seen_subcommand_from init" -s t -d "Project template" -r
complete -c wart -n "__fish_seen_subcommand_from init" -l name -d "Project name" -r
complete -c wart -n "__fish_seen_subcommand_from init" -s n -d "Project name" -r
