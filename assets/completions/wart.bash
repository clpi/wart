# Bash completion for wart
_wart_completion() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="run compile init package pkg workspace ws build pack deploy publish pub bench inspect config completion help version shell repl sh"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        run|inspect|compile)
            local opts="--debug --jit --aot --wat --wast --function --output --no-validate --color --no-color --cfile --cppfile --verbose --dump-objc"
            COMPREPLY=( $(compgen -W "$opts" -f -- "$cur") )
            ;;
        bench)
            local opts="--debug --jit --no-validate --color --no-color --verbose"
            COMPREPLY=( $(compgen -W "$opts" -f -- "$cur") )
            ;;
        completion)
            COMPREPLY=( $(compgen -W "bash zsh fish powershell elvish nu xonsh tcsh" -- "$cur") )
            ;;
        config)
            COMPREPLY=( $(compgen -W "init list get set reset" -- "$cur") )
            ;;
        init)
            COMPREPLY=( $(compgen -W "--template --name -t -n" -- "$cur") )
            ;;
        package|pkg|workspace|ws)
            COMPREPLY=( $(compgen -W "list add remove create info" -- "$cur") )
            ;;
        build|pack)
            COMPREPLY=( $(compgen -W "--output --source --workspace -o -s -w" -- "$cur") )
            ;;
        deploy|publish|pub)
            COMPREPLY=( $(compgen -W "--registry --dry-run --access -r -n -a" -- "$cur") )
            ;;
    esac
}
complete -F _wart_completion wart
