/**
 Framecloud API.
 */
window.framecloud = {
    reportAvailability: function () {
        console.debug("Reporting availability...");

        let body = {
            "reportAvailability": {}
        };

        window.webkit.messageHandlers.framecloud.postMessage(body);

        console.debug("Availability reported.");
    }
};
