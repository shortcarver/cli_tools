#!/bin/bash

# autoload -Uz bashcompinit && bashcompinit

alias tp='. ~/.local/share/cli_tools/tp.sh'
complete -W "cnflpr sr tp nvim vim code" tp

alias audible-convert='sh ~/.local/share/cli_tools/audible-convert.sh'


