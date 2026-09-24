# Base zsh config, symlinked to ~/.config/zshrc-base.zsh and sourced from the
# managed header in ~/.zshrc. Keep interactive-shell concerns here and
# environment/PATH concerns in bashrc-extra.

# Powerlevel10k instant prompt — must stay near the top; anything that may
# prompt for input has to run above it.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="${XDG_CONFIG_HOME}/oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git git-lfs zsh-autosuggestions zsh-syntax-highlighting)
source "${ZSH}/oh-my-zsh.sh"

# iTerm2 sends Option-Left/Right as CSI 1;3D/C. Bind them in both common
# editing modes so local and remote (tmux/mosh) shell prompts move by word.
for _keymap in emacs viins; do
  bindkey -M "${_keymap}" $'\e[1;3D' backward-word
  bindkey -M "${_keymap}" $'\e[1;3C' forward-word
done
unset _keymap

export POWERLEVEL9K_CONFIG_FILE="${XDG_CONFIG_HOME}/p10k.zsh"
[[ ! -f ${POWERLEVEL9K_CONFIG_FILE} ]] || source "${POWERLEVEL9K_CONFIG_FILE}"

# Machine-local interactive tweaks that should not be committed.
[[ ! -f "${XDG_CONFIG_HOME}/zshrc-local.zsh" ]] || source "${XDG_CONFIG_HOME}/zshrc-local.zsh"
