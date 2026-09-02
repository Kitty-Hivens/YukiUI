import QtQml

/**
 * Nothing runs in the shell for this one.
 *
 * The host requires an entry of every plugin, and this plugin exists to carry a
 * settings page: the reading and the writing both happen in the settings window,
 * on demand, against files on disk. A background object here would be a second
 * copy of that with nobody looking at it.
 */
QtObject {
    // Handed in by the host whether a plugin declares defaults or not.
    property var settings: null
}
