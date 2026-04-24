import Toybox.Lang;
import Toybox.WatchUi;

// StorageFullMenuDelegate: backs the two-row "Storage full" popup.
// onBack is equivalent to selecting "Don't store" — the user opted not
// to decide explicitly, so the safer choice is to stop storing further
// sets for this session (spec §11.2).
class StorageFullMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _buffer      as OutboundBufferService;
    private var _payload     as Dictionary;
    private var _sessionMeta as Dictionary;

    function initialize(
        buffer as OutboundBufferService,
        payload as Dictionary,
        sessionMeta as Dictionary
    ) {
        Menu2InputDelegate.initialize();
        _buffer      = buffer;
        _payload     = payload;
        _sessionMeta = sessionMeta;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :deleteOldest) {
            _buffer.resolveFull_deleteOldest(_payload, _sessionMeta);
        } else if (id == :dontStore) {
            _buffer.resolveFull_dontStore(_sessionMeta["sessionId"] as String);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        // BACK = "Don't store" (safer default than leaving buffer policy undecided).
        _buffer.resolveFull_dontStore(_sessionMeta["sessionId"] as String);
        // Return without popping — the framework pops the Menu2 automatically on back.
    }
}
