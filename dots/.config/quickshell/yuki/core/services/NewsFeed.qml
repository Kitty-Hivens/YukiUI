pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * The story feed behind the widgets board.
 *
 * The board this copies is fed by one publisher's aggregator. There is no
 * equivalent to point at, so this reads the feeds named in the configuration and
 * nothing else: with none named, and with the feed switched off, it never opens a
 * connection.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.waffles.widgets.feed.enable ?? false
    readonly property list<string> sources: Config.options?.waffles.widgets.feed.sources ?? []
    readonly property int refreshInterval: (Config.options?.waffles.widgets.feed.refreshInterval ?? 30) * 60 * 1000
    readonly property int maxArticles: Config.options?.waffles.widgets.feed.maxArticles ?? 40

    /** Newest first, across every source. */
    property list<var> articles: []
    property bool loading: false
    property int lastRefresh: 0

    property var articlesBySource: ({})

    onEnabledChanged: {
        if (root.enabled)
            root.refresh();
        else
            root.clear();
    }
    onSourcesChanged: {
        if (root.enabled)
            root.refresh();
    }

    function clear() {
        root.articlesBySource = ({});
        root.articles = [];
    }

    function refresh() {
        if (!root.enabled || root.sources.length === 0) {
            root.clear();
            return;
        }
        root.loading = true;
        root.sources.forEach(source => root.fetchSource(source));
    }

    function fetchSource(source) {
        const request = new XMLHttpRequest();
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            if (request.status === 200) {
                root.acceptSource(source, root.parseFeed(request.responseXML, source));
            } else {
                console.warn("[NewsFeed] could not read", source, "--", request.status);
                root.acceptSource(source, []);
            }
        };
        request.open("GET", source);
        request.send();
    }

    function acceptSource(source, parsed) {
        const collected = root.articlesBySource;
        collected[source] = parsed;
        root.articlesBySource = collected;

        var merged = [];
        for (const key of Object.keys(collected)) merged = merged.concat(collected[key]);
        merged.sort((a, b) => b.timestamp - a.timestamp);

        root.articles = merged.slice(0, root.maxArticles);
        root.loading = false;
        root.lastRefresh = root.articles.length > 0 ? root.articles[0].timestamp : 0;
    }

    function textOf(element, tagName) {
        const nodes = element.getElementsByTagName(tagName);
        if (!nodes || nodes.length === 0)
            return "";
        const node = nodes[0];
        return (node.textContent ?? "").trim();
    }

    function attributeOf(element, tagName, attribute) {
        const nodes = element.getElementsByTagName(tagName);
        for (var i = 0; i < (nodes?.length ?? 0); i++) {
            const value = nodes[i].attributes?.getNamedItem?.(attribute)?.value ?? "";
            if (value.length > 0)
                return value;
        }
        return "";
    }

    /** Handles both of the shapes a feed comes in: RSS items and Atom entries. */
    function parseFeed(document, source) {
        if (!document || !document.documentElement)
            return [];

        const root_ = document.documentElement;
        const feedTitle = root.textOf(root_, "title");

        var entries = Array.from(root_.getElementsByTagName("item") ?? []);
        const atom = entries.length === 0;
        if (atom)
            entries = Array.from(root_.getElementsByTagName("entry") ?? []);

        return entries.map(entry => {
            const title = root.textOf(entry, "title");
            const link = atom ? root.attributeOf(entry, "link", "href") : root.textOf(entry, "link");
            const dateText = atom ? (root.textOf(entry, "updated") || root.textOf(entry, "published")) : root.textOf(entry, "pubDate");
            const parsedDate = Date.parse(dateText);
            const image = root.attributeOf(entry, "enclosure", "url") || root.attributeOf(entry, "thumbnail", "url") || root.attributeOf(entry, "content", "url");
            return {
                title: title,
                link: link,
                image: image,
                source: feedTitle.length > 0 ? feedTitle : source,
                timestamp: isNaN(parsedDate) ? 0 : parsedDate
            };
        }).filter(article => article.title.length > 0);
    }

    Timer {
        running: root.enabled && root.sources.length > 0
        interval: root.refreshInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
