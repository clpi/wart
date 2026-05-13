# PowerShell completion for wart

using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Register-ArgumentCompleter -Native -CommandName 'wart' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $commandElements = $commandAst.CommandElements
    $command = @(
        'wart'
        for ($i = 1; $i -lt $commandElements.Count; $i++) {
            $element = $commandElements[$i]
            if ($element -isnot [StringConstantExpressionAst] -or
                $element.StringConstantType -ne [StringConstantType]::BareWord -or
                $element.Value.StartsWith('-') -or
                $element.Value -eq $wordToComplete) {
                break
            }
            $element.Value
        }
    ) -join ';'

    $completions = @(switch ($command) {
        'wart' {
            [CompletionResult]::new('run', 'run', [CompletionResultType]::ParameterValue, 'Execute a WebAssembly module')
            [CompletionResult]::new('compile', 'compile', [CompletionResultType]::ParameterValue, 'Compile WASM to native executable')
            [CompletionResult]::new('init', 'init', [CompletionResultType]::ParameterValue, 'Initialize a new wart project')
            [CompletionResult]::new('package', 'package', [CompletionResultType]::ParameterValue, 'Manage packages')
            [CompletionResult]::new('pkg', 'pkg', [CompletionResultType]::ParameterValue, 'Manage packages (alias)')
            [CompletionResult]::new('workspace', 'workspace', [CompletionResultType]::ParameterValue, 'Manage packages (alias)')
            [CompletionResult]::new('ws', 'ws', [CompletionResultType]::ParameterValue, 'Manage packages (alias)')
            [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, 'Create a distributable package')
            [CompletionResult]::new('pack', 'pack', [CompletionResultType]::ParameterValue, 'Create a distributable package (alias)')
            [CompletionResult]::new('deploy', 'deploy', [CompletionResultType]::ParameterValue, 'Deploy package to registry')
            [CompletionResult]::new('publish', 'publish', [CompletionResultType]::ParameterValue, 'Deploy package to registry (alias)')
            [CompletionResult]::new('pub', 'pub', [CompletionResultType]::ParameterValue, 'Deploy package to registry (alias)')
            [CompletionResult]::new('bench', 'bench', [CompletionResultType]::ParameterValue, 'Run benchmark suite')
            [CompletionResult]::new('inspect', 'inspect', [CompletionResultType]::ParameterValue, 'Inspect a WebAssembly module')
            [CompletionResult]::new('config', 'config', [CompletionResultType]::ParameterValue, 'Manage configuration')
            [CompletionResult]::new('completion', 'completion', [CompletionResultType]::ParameterValue, 'Generate completions')
            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Show help')
            [CompletionResult]::new('version', 'version', [CompletionResultType]::ParameterValue, 'Show version')
            [CompletionResult]::new('shell', 'shell', [CompletionResultType]::ParameterValue, 'Interactive WASM shell')
            [CompletionResult]::new('repl', 'repl', [CompletionResultType]::ParameterValue, 'Interactive WASM shell (alias)')
            [CompletionResult]::new('sh', 'sh', [CompletionResultType]::ParameterValue, 'Interactive WASM shell (alias)')
            break
        }
        { $_ -in 'wart;run', 'wart;inspect', 'wart;compile' } {
            [CompletionResult]::new('--debug', '--debug', [CompletionResultType]::ParameterName, 'Enable debug output')
            [CompletionResult]::new('-d', '-d', [CompletionResultType]::ParameterName, 'Enable debug output')
            [CompletionResult]::new('--jit', '--jit', [CompletionResultType]::ParameterName, 'Enable JIT compilation')
            [CompletionResult]::new('-j', '-j', [CompletionResultType]::ParameterName, 'Enable JIT compilation')
            [CompletionResult]::new('--aot', '--aot', [CompletionResultType]::ParameterName, 'Enable AOT compilation')
            [CompletionResult]::new('-a', '-a', [CompletionResultType]::ParameterName, 'Enable AOT compilation')
            [CompletionResult]::new('--wat', '--wat', [CompletionResultType]::ParameterName, 'Force WAT parsing')
            [CompletionResult]::new('-w', '-w', [CompletionResultType]::ParameterName, 'Force WAT parsing')
            [CompletionResult]::new('--wast', '--wast', [CompletionResultType]::ParameterName, 'Force WAST parsing')
            [CompletionResult]::new('--function', '--function', [CompletionResultType]::ParameterName, 'Specify function to execute')
            [CompletionResult]::new('-f', '-f', [CompletionResultType]::ParameterName, 'Specify function to execute')
            [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, 'Output file for AOT')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'Output file for AOT')
            [CompletionResult]::new('--cfile', '--cfile', [CompletionResultType]::ParameterName, 'Compile C source to WASM')
            [CompletionResult]::new('-c', '-c', [CompletionResultType]::ParameterName, 'Compile C source to WASM')
            [CompletionResult]::new('--cppfile', '--cppfile', [CompletionResultType]::ParameterName, 'Compile C++ source to WASM')
            [CompletionResult]::new('-C', '-C', [CompletionResultType]::ParameterName, 'Compile C++ source to WASM')
            [CompletionResult]::new('--no-validate', '--no-validate', [CompletionResultType]::ParameterName, 'Skip WASM validation')
            [CompletionResult]::new('--color', '--color', [CompletionResultType]::ParameterName, 'Enable colored output')
            [CompletionResult]::new('--no-color', '--no-color', [CompletionResultType]::ParameterName, 'Disable colored output')
            [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, 'Set verbosity level')
            [CompletionResult]::new('-V', '-V', [CompletionResultType]::ParameterName, 'Set verbosity level')
            break
        }
        'wart;bench' {
            [CompletionResult]::new('--debug', '--debug', [CompletionResultType]::ParameterName, 'Enable debug output')
            [CompletionResult]::new('-d', '-d', [CompletionResultType]::ParameterName, 'Enable debug output')
            [CompletionResult]::new('--jit', '--jit', [CompletionResultType]::ParameterName, 'Enable JIT compilation')
            [CompletionResult]::new('-j', '-j', [CompletionResultType]::ParameterName, 'Enable JIT compilation')
            [CompletionResult]::new('--no-validate', '--no-validate', [CompletionResultType]::ParameterName, 'Skip WASM validation')
            [CompletionResult]::new('--color', '--color', [CompletionResultType]::ParameterName, 'Enable colored output')
            [CompletionResult]::new('--no-color', '--no-color', [CompletionResultType]::ParameterName, 'Disable colored output')
            [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, 'Set verbosity level')
            [CompletionResult]::new('-V', '-V', [CompletionResultType]::ParameterName, 'Set verbosity level')
            break
        }
        { $_ -in 'wart;package', 'wart;pkg', 'wart;workspace', 'wart;ws' } {
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List packages')
            [CompletionResult]::new('add', 'add', [CompletionResultType]::ParameterValue, 'Add a package')
            [CompletionResult]::new('remove', 'remove', [CompletionResultType]::ParameterValue, 'Remove a package')
            [CompletionResult]::new('create', 'create', [CompletionResultType]::ParameterValue, 'Create a new package')
            [CompletionResult]::new('info', 'info', [CompletionResultType]::ParameterValue, 'Show package info')
            break
        }
        { $_ -in 'wart;build', 'wart;pack' } {
            [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, 'Output file path')
            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'Output file path')
            [CompletionResult]::new('--source', '--source', [CompletionResultType]::ParameterName, 'Include source files')
            [CompletionResult]::new('-s', '-s', [CompletionResultType]::ParameterName, 'Include source files')
            [CompletionResult]::new('--workspace', '--workspace', [CompletionResultType]::ParameterName, 'Package all workspace members')
            [CompletionResult]::new('-w', '-w', [CompletionResultType]::ParameterName, 'Package all workspace members')
            break
        }
        { $_ -in 'wart;deploy', 'wart;publish', 'wart;pub' } {
            [CompletionResult]::new('--registry', '--registry', [CompletionResultType]::ParameterName, 'Registry to deploy to')
            [CompletionResult]::new('-r', '-r', [CompletionResultType]::ParameterName, 'Registry to deploy to')
            [CompletionResult]::new('--dry-run', '--dry-run', [CompletionResultType]::ParameterName, 'Dry run')
            [CompletionResult]::new('-n', '-n', [CompletionResultType]::ParameterName, 'Dry run')
            [CompletionResult]::new('--access', '--access', [CompletionResultType]::ParameterName, 'Access level (public, private, restricted)')
            [CompletionResult]::new('-a', '-a', [CompletionResultType]::ParameterName, 'Access level (public, private, restricted)')
            break
        }
        'wart;config' {
            [CompletionResult]::new('init', 'init', [CompletionResultType]::ParameterValue, 'Initialize configuration')
            [CompletionResult]::new('list', 'list', [CompletionResultType]::ParameterValue, 'List all configuration')
            [CompletionResult]::new('get', 'get', [CompletionResultType]::ParameterValue, 'Get configuration value')
            [CompletionResult]::new('set', 'set', [CompletionResultType]::ParameterValue, 'Set configuration value')
            [CompletionResult]::new('reset', 'reset', [CompletionResultType]::ParameterValue, 'Reset configuration')
            break
        }
        'wart;completion' {
            [CompletionResult]::new('bash', 'bash', [CompletionResultType]::ParameterValue, 'Bash shell')
            [CompletionResult]::new('zsh', 'zsh', [CompletionResultType]::ParameterValue, 'Zsh shell')
            [CompletionResult]::new('fish', 'fish', [CompletionResultType]::ParameterValue, 'Fish shell')
            [CompletionResult]::new('powershell', 'powershell', [CompletionResultType]::ParameterValue, 'PowerShell')
            [CompletionResult]::new('elvish', 'elvish', [CompletionResultType]::ParameterValue, 'Elvish shell')
            [CompletionResult]::new('nu', 'nu', [CompletionResultType]::ParameterValue, 'Nushell')
            [CompletionResult]::new('xonsh', 'xonsh', [CompletionResultType]::ParameterValue, 'Xonsh shell')
            [CompletionResult]::new('tcsh', 'tcsh', [CompletionResultType]::ParameterValue, 'Tcsh shell')
            break
        }
        'wart;init' {
            [CompletionResult]::new('--template', '--template', [CompletionResultType]::ParameterName, 'Project template')
            [CompletionResult]::new('-t', '-t', [CompletionResultType]::ParameterName, 'Project template')
            [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, 'Project name')
            [CompletionResult]::new('-n', '-n', [CompletionResultType]::ParameterName, 'Project name')
            break
        }
    })

    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
        Sort-Object -Property ListItemText
}
