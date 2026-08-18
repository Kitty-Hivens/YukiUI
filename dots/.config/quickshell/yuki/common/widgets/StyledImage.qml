import QtQuick
import Quickshell
import qs.core.services
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.common

Image {
    id: root
    asynchronous: true
    retainWhileLoading: true
    visible: opacity > 0
    opacity: (status === Image.Ready) ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    /**
     * A chain of paths to try in order. Set `primarySource` rather than `source` to
     * use it: the chain is resolved by binding, and writing to `source` on failure --
     * which is what this used to do -- destroys whatever binding the caller put
     * there. In a reused delegate that leaves the previous row's picture on screen,
     * and once the chain ran out the element stayed pinned to the last fallback for
     * the rest of its life, deaf to its own source changing back.
     */
    property string primarySource: ""
    property list<string> fallbacks: []
    property int currentFallbackIndex: 0
    readonly property var sourceChain: [root.primarySource].concat(Array.from(root.fallbacks))

    source: root.sourceChain[Math.min(root.currentFallbackIndex, root.sourceChain.length - 1)]

    // A new subject starts the chain over, so a delegate handed the next row's
    // picture tries its best path again instead of inheriting the last one's defeat.
    onPrimarySourceChanged: root.currentFallbackIndex = 0
    onFallbacksChanged: root.currentFallbackIndex = 0

    onStatusChanged: {
        if (root.status === Image.Error && root.currentFallbackIndex < root.fallbacks.length)
            root.currentFallbackIndex += 1;
    }

    sourceSize: {
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        return Qt.size(width * dpr, height * dpr);
    }
}
