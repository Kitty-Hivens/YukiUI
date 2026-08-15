import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: root

    signal done(string path, int width, int height);
    required property string filePath;
    required property string sourceUrl;
    property string downloadUserAgent: Config.options?.networking.userAgent ?? ""
    property string referer: ""

    function processFilePath() {
        return StringUtils.shellSingleQuoteEscape(FileUtils.trimFileProtocol(filePath));
    }

    function processSourceUrl() {
        return StringUtils.shellSingleQuoteEscape(sourceUrl);
    }

    function curlUserAgentArg() {
        if (!downloadUserAgent) {
            return "";
        }
        return ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(downloadUserAgent)}'`;
    }

    function curlRefererArg() {
        if (!referer) {
            return "";
        }
        return ` -H 'Referer: ${StringUtils.shellSingleQuoteEscape(referer)}'`;
    }

    running: true
    // --fail --remove-on-error so a host that answers with an error page doesn't
    // leave that page cached under the picture's name for good.
    command: ["bash", "-c",
        `mkdir -p $(dirname '${processFilePath()}'); [ -f '${processFilePath()}' ] || curl -sSLf --remove-on-error '${processSourceUrl()}'${curlUserAgentArg()}${curlRefererArg()} -o '${processFilePath()}' && file '${processFilePath()}'`
    ]
    stdout: StdioCollector {
        id: imageSizeOutputCollector
        onStreamFinished: {
            const output = imageSizeOutputCollector.text.trim();
            // Empty means curl failed and `file` never ran, so there is nothing to report.
            if (output.length === 0) {
                return;
            }
            // `file` doesn't name the dimensions of every format it recognises. The
            // download still happened, and saying so is the point of this signal --
            // holding it back over a missing width leaves the caller with no picture.
            const match = output.match(/(\d+)\s*x\s*(\d+)/);
            root.done(root.filePath, match ? Number(match[1]) : 0, match ? Number(match[2]) : 0);
        }
    }
}
