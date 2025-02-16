#!/bin/bash
loc=$1

if [[ "$loc" = "tp" ]]; then
	cd ~/.local/share/cli_tools/
elif [[ "$loc" = "nvim" ]] || [[ "$loc" = "vim" ]]; then
	cd ~/.config/nvim/
elif [[ "$loc" = "cnflpr" ]]; then
	cd ~/Code/cnflpr-org/
elif [[ "$loc" = "sr" ]]; then
	cd ~/Code/scenic_route/
fi

