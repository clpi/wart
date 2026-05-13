# Xonsh completion for wart
from argparse import ArgumentParser

def _wart_completer(prefix, line, begidx, endidx, ctx):
    """Completer for wart command"""
    args = line.split()

    # Complete commands
    if len(args) <= 1 or (len(args) == 2 and not line.endswith(' ')):
        commands = ['run', 'compile', 'init', 'package', 'pkg', 'workspace', 'ws',
                   'build', 'pack', 'deploy', 'publish', 'pub', 'bench', 'inspect',
                   'config', 'completion', 'help', 'version', 'shell', 'repl', 'sh']
        return {cmd for cmd in commands if cmd.startswith(prefix)}

    command = args[1]

    # Complete subcommands and options
    if command in ['run', 'inspect', 'compile']:
        options = ['--debug', '-d', '--jit', '-j', '--aot', '-a', '--wat', '-w',
                  '--wast', '--function', '-f', '--output', '-o', '--cfile', '-c',
                  '--cppfile', '-C', '--no-validate', '--color', '--no-color',
                  '--verbose', '-V', '--dump-objc']
        return {opt for opt in options if opt.startswith(prefix)}

    elif command == 'bench':
        options = ['--debug', '-d', '--jit', '-j', '--no-validate', '--color',
                  '--no-color', '--verbose', '-V']
        return {opt for opt in options if opt.startswith(prefix)}

    elif command in ['package', 'pkg', 'workspace', 'ws']:
        if len(args) == 2 or (len(args) == 3 and not line.endswith(' ')):
            actions = ['list', 'add', 'remove', 'create', 'info']
            return {act for act in actions if act.startswith(prefix)}

    elif command in ['build', 'pack']:
        options = ['--output', '-o', '--source', '-s', '--workspace', '-w']
        return {opt for opt in options if opt.startswith(prefix)}

    elif command in ['deploy', 'publish', 'pub']:
        options = ['--registry', '-r', '--dry-run', '-n', '--access', '-a']
        return {opt for opt in options if opt.startswith(prefix)}

    elif command == 'config':
        if len(args) == 2 or (len(args) == 3 and not line.endswith(' ')):
            actions = ['init', 'list', 'get', 'set', 'reset']
            return {act for act in actions if act.startswith(prefix)}

    elif command == 'completion':
        if len(args) == 2 or (len(args) == 3 and not line.endswith(' ')):
            shells = ['bash', 'zsh', 'fish', 'powershell', 'elvish', 'nu', 'xonsh', 'tcsh']
            return {sh for sh in shells if sh.startswith(prefix)}

    elif command == 'init':
        options = ['--template', '-t', '--name', '-n']
        return {opt for opt in options if opt.startswith(prefix)}

    return set()

# Register the completer
completer add wart _wart_completer 'start'
