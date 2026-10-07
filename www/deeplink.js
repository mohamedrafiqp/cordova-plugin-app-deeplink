var exec = require('cordova/exec');

var SERVICE = 'DeepLink';
var listeners = [];
var subscribed = false;

function notify(result) {
    var url = typeof result === 'string' ? result : result && result.url;
    if (!url) return;
    for (var i = 0; i < listeners.length; i++) {
        try {
            listeners[i](url);
        } catch (e) {
            // listener errors must never break the delivery chain
        }
    }
}

function startSubscription() {
    if (subscribed) return;
    subscribed = true;
    exec(
        notify,
        function () {
            // native side went away, allow a later re-subscribe
            subscribed = false;
        },
        SERVICE,
        'subscribe',
        []
    );
}

module.exports = {
    /**
     * Registers a listener that receives every incoming deep link URL.
     * URLs captured before this call (app cold start) are delivered right
     * after the subscription is registered.
     */
    subscribe: function (listener) {
        if (typeof listener === 'function') {
            listeners.push(listener);
        }
        startSubscription();
    },
};
