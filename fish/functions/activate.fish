function activate --description 'Activate a Python venv (default: ./.venv)'
    set -l dir .venv
    if test -n "$argv[1]"
        set dir $argv[1]
    end

    if test -f "$dir/bin/activate.fish"
        source "$dir/bin/activate.fish"
    else
        echo "activate: no venv found at '$dir' (expected $dir/bin/activate.fish)" >&2
        return 1
    end
end
