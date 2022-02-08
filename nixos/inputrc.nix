{
  environment.etc."inputrc".text = ''
    # Modified from default 20200522

    set meta-flag on
    set input-meta on
    set convert-meta off
    set output-meta on
    set colored-stats on

    set show-all-if-ambiguous on
    set completion-ignore-case on
    set completion-map-case on
    set bell-style none
    set echo-control-characters off

    "\e[A": history-search-backward
    "\e[B": history-search-forward

    #set mark-symlinked-directories on

    $if mode=emacs

    # for linux console and RH/Debian xterm
    "\e[1~": beginning-of-line
    "\e[4~": end-of-line
    "\e[5~": beginning-of-history
    "\e[6~": end-of-history
    "\e[3~": delete-char
    "\e[2~": quoted-insert
    "\e[5C": forward-word
    "\e[5D": backward-word
    "\e[1;5C": forward-word
    "\e[1;5D": backward-word

    # for rxvt
    "\e[8~": end-of-line

    # for non RH/Debian xterm, can't hurt for RH/DEbian xterm
    "\eOH": beginning-of-line
    "\eOF": end-of-line

    # for freebsd console
    "\e[H": beginning-of-line
    "\e[F": end-of-line
    $endif
  '';
}
