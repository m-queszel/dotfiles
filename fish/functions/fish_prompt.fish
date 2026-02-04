function fish_prompt
    set_color red
    echo -n (whoami)
    set_color normal
    echo -n '@'(hostname)' '
    set_color red
    echo -n (prompt_pwd)
    set_color normal
    echo -n ' > '
end