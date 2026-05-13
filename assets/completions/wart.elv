# Elvish completion for wart

set edit:completion:arg-completer[wart] = {|@words|
    set n = (count $words)
    if (== $n 2) {
        put run compile init package pkg workspace ws build pack deploy publish pub bench inspect config completion help version shell repl sh
    } elif (== $n 3) {
        if (or (eq $words[1] run) (eq $words[1] inspect) (eq $words[1] compile)) {
            put --debug -d --jit -j --aot -a --wat -w --wast --function -f --output -o --cfile -c --cppfile -C --no-validate --color --no-color --verbose -V
        } elif (eq $words[1] bench) {
            put --debug -d --jit -j --no-validate --color --no-color --verbose -V
        } elif (or (eq $words[1] package) (eq $words[1] pkg) (eq $words[1] workspace) (eq $words[1] ws)) {
            put list add remove create info
        } elif (or (eq $words[1] build) (eq $words[1] pack)) {
            put --output -o --source -s --workspace -w
        } elif (or (eq $words[1] deploy) (eq $words[1] publish) (eq $words[1] pub)) {
            put --registry -r --dry-run -n --access -a
        } elif (eq $words[1] config) {
            put init list get set reset
        } elif (eq $words[1] completion) {
            put bash zsh fish powershell elvish nu xonsh tcsh
        } elif (eq $words[1] init) {
            put --template -t --name -n
        }
    }
}
