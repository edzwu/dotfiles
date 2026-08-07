# gtags (GNU Global) configuration
# Loaded by ~/.profile via profile.d mechanism

# Use gtags' builtin parser so GRTAGS contains full call-site references.
# The universal-ctags plugin mainly provides definitions and include references,
# which makes \cs / global -r incomplete. Python/Go navigation is handled by LSP.
export GTAGSLABEL='default'
export GTAGSCONF="$HOME/.global/gtags.conf"
