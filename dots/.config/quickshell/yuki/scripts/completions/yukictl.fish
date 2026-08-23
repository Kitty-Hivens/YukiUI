# What a shell may offer after `yukictl`.
#
# The ids are asked of the command itself, which asks the running shell for
# them: the registries live there, so a completion that walked the directories
# would be a second opinion about what is installed. Every spelling the command
# accepts is listed, so completing after `plugin` works as it does after
# `plugins`.

set -l plugins plugins plugin
set -l environments env environment environments
set -l verbs list enable disable use

# Nothing here takes a file, and offering the working directory instead of an id
# is worse than offering nothing.
complete -c yukictl -f

complete -c yukictl -n __fish_use_subcommand -a plugins -d 'what is built on top of the shell'
complete -c yukictl -n __fish_use_subcommand -a env -d 'the part of the shell that is up'
complete -c yukictl -n __fish_use_subcommand -a help -d 'what all of this does'

complete -c yukictl -n "__fish_seen_subcommand_from $plugins; and not __fish_seen_subcommand_from $verbs" \
    -a list -d 'what is installed, what runs, what is wrong'
complete -c yukictl -n "__fish_seen_subcommand_from $plugins; and not __fish_seen_subcommand_from $verbs" \
    -a enable -d 'build it from now on'
complete -c yukictl -n "__fish_seen_subcommand_from $plugins; and not __fish_seen_subcommand_from $verbs" \
    -a disable -d 'take it down and leave it down'

complete -c yukictl -n "__fish_seen_subcommand_from $environments; and not __fish_seen_subcommand_from $verbs" \
    -a list -d 'installed environments and which one is up'
complete -c yukictl -n "__fish_seen_subcommand_from $environments; and not __fish_seen_subcommand_from $verbs" \
    -a use -d 'switch to it, turning it back on if it was off'

complete -c yukictl -n "__fish_seen_subcommand_from $plugins; and __fish_seen_subcommand_from enable disable" \
    -a '(yukictl __complete plugins)'
complete -c yukictl -n "__fish_seen_subcommand_from $environments; and __fish_seen_subcommand_from use" \
    -a '(yukictl __complete env)'
