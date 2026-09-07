// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Clicks Nextcloud's notifications bell, if present, to open the panel it hangs
// in the page header.
//
// The selector comes from <html>, where NotificationsPanelState.js published
// whichever of its candidates matched, so the search for that control happens in
// one place and this script holds no knowledge of the page's markup at all. A
// document that never ran that script carries no attribute and nothing happens
// here, which — as with SidebarToggle.js against a page that offers no
// app-navigation toggle — is the whole of the fix.
//
// The bell toggles, and this must not: the account menu that offers it is native
// and closes without ever dispatching a pointer event into the page, so the
// panel can still be open when the item is chosen, and clicking then would close
// it and read as the item doing nothing. Where it is already open, opening it
// again is nothing to do.
//
// The click lands even though the header is display: none, as SidebarToggle.js's
// already does through that same rule, and Cirruscope.css is what makes the panel
// it opens actually visible.

(function() {
    var selector = document.documentElement.getAttribute('data-cirruscope-notifications-trigger');

    if (!selector) {
        return;
    }

    var element = document.querySelector(selector);

    if (!element) {
        return;
    }

    if (element.getAttribute('aria-expanded') === 'true') {
        return;
    }

    element.click();
})();
