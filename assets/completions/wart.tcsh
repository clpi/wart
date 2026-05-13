# Tcsh completion for wart
complete wart 'p/1/(run compile init package pkg workspace ws build pack deploy publish pub bench inspect config completion help version shell repl sh)/' \
    'n/run/(--debug --jit --aot --wat --wast --function --output --cfile --cppfile --no-validate --color --no-color --verbose --dump-objc)/' \
    'n/compile/(--debug --jit --aot --wat --wast --function --output --cfile --cppfile --no-validate --color --no-color --verbose --dump-objc)/' \
    'n/inspect/(--debug --jit --aot --wat --wast --function --output --cfile --cppfile --no-validate --color --no-color --verbose --dump-objc)/' \
    'n/bench/(--debug --jit --no-validate --color --no-color --verbose)/' \
    'n/package/(list add remove create info)/' \
    'n/pkg/(list add remove create info)/' \
    'n/workspace/(list add remove create info)/' \
    'n/ws/(list add remove create info)/' \
    'n/build/(--output --source --workspace)/' \
    'n/pack/(--output --source --workspace)/' \
    'n/deploy/(--registry --dry-run --access)/' \
    'n/publish/(--registry --dry-run --access)/' \
    'n/pub/(--registry --dry-run --access)/' \
    'n/config/(init list get set reset)/' \
    'n/completion/(bash zsh fish powershell elvish nu xonsh tcsh)/' \
    'n/init/(--template --name)/'
