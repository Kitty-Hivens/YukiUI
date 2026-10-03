pragma ComponentBehavior: Bound
pragma Singleton
import qs.core
import qs.core.utils
import qs.core.functions
import qs.common.widgets
import qs.core.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    /**
     * The command for an action on a region of a screenshot.
     *
     * Every value goes in as an argument of the script rather than spliced
     * into it: the screenshot's path was escaped for single quotes and then
     * left unquoted, so a space in it broke the crop, and the folder to save
     * in was put between double quotes unescaped.
     *
     * The arguments, as the scripts read them: $1 the screenshot, $2 the
     * region as magick takes it, and after that what the action needs.
     */
    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        const crop = `${rw}x${rh}+${rx}+${ry}`;
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`;
        const run = (script, ...extra) => ["bash", "-c", script, "screenshot-action", screenshotPath, crop, ...extra];
        switch (action) {
            case ScreenshotAction.Action.Copy:
                if (saveDir === "")
                    return run('magick "$1" -crop "$2" +repage - | wl-copy && rm -- "$1"');
                return run('mkdir -p -- "$3" && savePath="$3/screenshot-$(date +%Y-%m-%d_%H.%M.%S).png" && '
                    + 'magick "$1" -crop "$2" +repage - | tee >(wl-copy) > "$savePath" && rm -- "$1"', saveDir);
            case ScreenshotAction.Action.Edit:
                return run('magick "$1" -crop "$2" +repage - | "$3" -f - && rm -- "$1"',
                    Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy");
            case ScreenshotAction.Action.Search:
                return run('magick "$1" -crop "$2" +repage "$1" && '
                    + 'url=$(curl -sF "files[]=@$1" "$4" | jq -r ".files[0].url") && xdg-open "$3$url" && rm -- "$1"',
                    root.imageSearchEngineBaseUrl, root.fileUploadApiEndpoint);
            case ScreenshotAction.Action.CharRecognition:
                return run('magick "$1" -crop "$2" +repage "$1" && '
                    + 'tesseract "$1" stdout -l "$(tesseract --list-langs | awk \'NR>1{print $1}\' | paste -sd+)" | wl-copy && rm -- "$1"');
            case ScreenshotAction.Action.Record:
                return ["bash", FileUtils.trimFileProtocol(Directories.recordScriptPath), "--region", slurpRegion];
            case ScreenshotAction.Action.RecordWithSound:
                return ["bash", FileUtils.trimFileProtocol(Directories.recordScriptPath), "--region", slurpRegion, "--sound"];
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
