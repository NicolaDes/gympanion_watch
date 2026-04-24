import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// FlushKickingConnectionListener: used as the ConnectionListener for live
// (non-replay) transmits. On success, kicks a flush so any buffered data
// from a previous disconnect drains behind the successful live send.
class FlushKickingConnectionListener extends Communications.ConnectionListener {
    private var _buffer as OutboundBufferService;

    function initialize(buffer as OutboundBufferService) {
        ConnectionListener.initialize();
        _buffer = buffer;
    }

    function onComplete() as Void {
        _buffer.flushIfPossible();
    }

    function onError() as Void {
        System.println("[Comm] live transmit error (poll timer will retry)");
    }
}
