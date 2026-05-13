#compdef wart
_wart() {
    local -a commands
    commands=(
        'run:Execute a WebAssembly module'
        'compile:Compile WASM to native executable'
        'init:Initialize a new wart project'
        'package:Manage packages'
        'pkg:Manage packages (alias)'
        'workspace:Manage packages (alias)'
        'ws:Manage packages (alias)'
        'build:Create a distributable package'
        'pack:Create a distributable package (alias)'
        'deploy:Deploy package to registry'
        'publish:Deploy package to registry (alias)'
        'pub:Deploy package to registry (alias)'
        'bench:Run benchmark suite'
        'inspect:Inspect a WebAssembly module'
        'config:Manage configuration'
        'completion:Generate completions'
        'help:Show help'
        'version:Show version'
        'shell:Interactive WASM shell'
        'repl:Interactive WASM shell (alias)'
        'sh:Interactive WASM shell (alias)'
    )
    local -a run_options
    run_options=(
        '--debug[Enable debug output]'
        '--jit[Enable JIT compilation]'
        '--aot[Enable AOT compilation]'
        '--wat[Force WAT parsing]'
        '--wast[Force WAST parsing]'
        '--function[Specify function to execute]:function'
        '--output[Output file for AOT]:file'
        '--cfile[Compile C source to WASM]:file'
        '--cppfile[Compile C++ source to WASM]:file'
        '--no-validate[Skip WASM validation]'
        '--color[Enable colored output]'
        '--no-color[Disable colored output]'
        '--verbose[Set verbosity level]:level'
        '--dump-objc[Dump object code]'
    )
    local -a bench_options
    bench_options=(
        '--debug[Enable debug output]'
        '--jit[Enable JIT compilation]'
        '--no-validate[Skip WASM validation]'
        '--color[Enable colored output]'
        '--no-color[Disable colored output]'
        '--verbose[Set verbosity level]:level'
    )
    local -a package_actions
    package_actions=(
        'list:List packages'
        'add:Add a package'
        'remove:Remove a package'
        'create:Create a new package'
        'info:Show package info'
    )
    local -a build_options
    build_options=(
        '--output[Output file path]:file'
        '-o[Output file path]:file'
        '--source[Include source files]'
        '-s[Include source files]'
        '--workspace[Package all workspace members]'
        '-w[Package all workspace members]'
    )
    local -a deploy_options
    deploy_options=(
        '--registry[Registry to deploy to]:url'
        '-r[Registry to deploy to]:url'
        '--dry-run[Dry run]'
        '-n[Dry run]'
        '--access[Access level]:access:(public private restricted)'
        '-a[Access level]:access:(public private restricted)'
    )
    local -a config_actions
    config_actions=(
        'init:Initialize configuration'
        'list:List all configuration'
        'get:Get configuration value'
        'set:Set configuration value'
        'reset:Reset configuration'
    )
    local -a shells
    shells=(
        'bash:Bash shell'
        'zsh:Zsh shell'
        'fish:Fish shell'
        'powershell:PowerShell'
        'elvish:Elvish shell'
        'nu:Nushell'
        'xonsh:Xonsh shell'
        'tcsh:Tcsh shell'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' commands
    else
        case "$words[2]" in
            run|inspect|compile)
                _arguments -s : $run_options '*:file:_files'
                ;;
            bench)
                _arguments -s : $bench_options '*:file:_files'
                ;;
            package|pkg|workspace|ws)
                _describe 'action' package_actions
                ;;
            build|pack)
                _arguments -s : $build_options
                ;;
            deploy|publish|pub)
                _arguments -s : $deploy_options
                ;;
            config)
                _describe 'action' config_actions
                ;;
            completion)
                _describe 'shell' shells
                ;;
        esac
    fi
}
_wart "$@"
