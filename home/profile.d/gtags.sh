# gtags (GNU Global) configuration
# Loaded by ~/.profile via profile.d mechanism

# native-pygments: builtin parser (C-family with full call-site references in
# GRTAGS) takes priority, pygments falls back for TS/JS/Python etc. (provides
# definitions + symbol references).
# Previously disabled because the pygments parser required /usr/bin/ctags-exuberant
# which is missing on macOS; Homebrew's current global (6.6.14) uses
# universal-ctags and bundles pygments in its libexec python, so it works now.
# Note: pygments is a lexer, so \cc/\cd (call chain) is still unreliable for TS;
# use LSP references (\lr) for that.
export GTAGSLABEL='native-pygments'
export GTAGSCONF="$HOME/.global/gtags.conf"
