# What a shell may offer after `yukictl`.
#
# The ids are asked of the command itself, which asks the running shell for
# them: the registries live there, so a completion that walked the directories
# would be a second opinion about what is installed. What each id is doing is
# printed beside it and has nowhere to go here, so only the name is kept.

_yukictl() {
    # Emptied first: what is left here from the last word completed is what the
    # shell offers when this one has nothing to say.
    COMPREPLY=()

    local cur=${COMP_WORDS[COMP_CWORD]}
    local group=${COMP_WORDS[1]} verb=${COMP_WORDS[2]}
    local words=

    case $COMP_CWORD in
        1)
            words="plugins env help"
            ;;
        2)
            case $group in
                plugins|plugin) words="list enable disable" ;;
                env|environment|environments) words="list use" ;;
            esac
            ;;
        3)
            case $group in
                plugins|plugin)
                    case $verb in
                        enable|disable) words=$(yukictl __complete plugins | cut -f1) ;;
                    esac
                    ;;
                env|environment|environments)
                    case $verb in
                        use) words=$(yukictl __complete env | cut -f1) ;;
                    esac
                    ;;
            esac
            ;;
    esac

    if [ -n "$words" ]; then
        mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
    fi
    return 0
}

complete -F _yukictl yukictl
