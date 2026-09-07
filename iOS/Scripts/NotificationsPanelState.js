// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Resolves Nextcloud's notifications menu in the page header, publishes the
// selector that found it onto <html>, and reports what it found and whether the
// panel is open through the `notificationsPanelState` message handler — once on
// injection and again whenever either answer changes.
//
// The menu is @nextcloud/vue's NcHeaderMenu, which the notifications app mounts
// into the <div id="notifications"> that core's layout.user.php puts inside
// #header. Verified against Nextcloud 34 and 32; from 32 on Vue 3 keeps the
// mount point, so two elements carry that id and every selector below is
// written to hold either way. Nothing further forward could be verified at all,
// which is why the candidates are a list and why the one that matched is
// reported back: after one hand test against a live server the log says what the
// DOM really is, instead of leaving it to be guessed at a second time.
//
// The candidates are ordered, and each rests on a different assumption, so a
// rename upstream costs one entry rather than the feature: the component's own
// class, then the ARIA relationship NcHeaderMenu derives from the app's id, then
// the class the notifications app puts on the menu, then the first button in the
// mount point at all. aria-label is deliberately not among them — it is
// localized, so matching it would fail on a German server.
//
// The open state is read from the trigger's aria-expanded rather than from the
// .header-menu--opened class, an ARIA contract being the more durable of the
// two, and it is the same attribute SidebarToggleState.js already reads.
//
// The selector goes on <html> for the reason SafeAreaInsets.js and
// AppearanceAttributes.js put their values there: Nextcloud owns <body>'s
// attributes and rewrites them as themes change, so <html> is the one element
// nothing on the page competes for. It is the channel NotificationsPanel.js
// reads, so the candidate list exists in exactly one place. A window global
// would have been the alternative — NotificationBridge.js uses one on macOS —
// and was rejected because a global is visible only in the content world that
// defined it, and whether an evaluated script and a user script share a world is
// precisely the kind of thing that fails silently and looks identical to the
// selector being wrong. Writing the attribute cannot re-enter the observer
// below, whose filter does not name it.
//
// State is reported only when it changes, not on every mutation. Nextcloud
// mutates its DOM continuously, and a message that means "something actually
// happened" is what lets the native side log every one of them at .notice
// without flooding the log store.

(function() {
    var candidates = [
        '#notifications .header-menu__trigger',
        '#notifications button[aria-controls="header-menu-notifications"]',
        '.notifications-button .header-menu__trigger',
        '#notifications button'
    ];

    var reported = '';

    function resolve() {
        for (var index = 0; index < candidates.length; index++) {
            var element = document.querySelector(candidates[index]);

            if (element) {
                return { element: element, selector: candidates[index] };
            }
        }

        return null;
    }

    function reportState() {
        var match = resolve();
        var available = !!match;
        var open = available && match.element.getAttribute('aria-expanded') === 'true';
        var selector = available ? match.selector : '';
        var state = available + '|' + open + '|' + selector;

        if (state === reported) {
            return;
        }

        if (available) {
            document.documentElement.setAttribute('data-cirruscope-notifications-trigger', selector);
        } else {
            document.documentElement.removeAttribute('data-cirruscope-notifications-trigger');
        }

        try {
            window.webkit.messageHandlers.notificationsPanelState.postMessage({
                available: available,
                open: open,
                selector: selector
            });

            reported = state;
        } catch (error) {
            // The native message handler is unavailable; leave the state unreported.
        }
    }

    reportState();

    var observer = new MutationObserver(function() {
        reportState();
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['aria-expanded', 'class']
    });
})();
