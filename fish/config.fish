if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Add local binaries to PATH
fish_add_path ~/.local/bin
# Add Composer global binaries to PATH
fish_add_path ~/.config/composer/vendor/bin



function fish_greeting
    if set -q fish_greeting_last_exit_time
        set -l current_time (date +%s)
        set -l duration (math $current_time - $fish_greeting_last_exit_time)
        echo "Welcome back! It has been" (string trim (date -d @$duration -u +%Hh\ %Mm\ %Ss)) "since your last session."
    end
    set -g fish_greeting_last_exit_time (date +%s)
end