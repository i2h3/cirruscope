// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Reports the height of Nextcloud's header through the `headerHeight` message
// handler, once on injection and again whenever the header is resized, so the
// host window can center its traffic lights inside a bar the server sizes
// rather than inside a height the app assumed (issue #102).
//
// The element's own bounding rect is measured rather than the --header-height
// custom property Nextcloud declares it from: the rect is what actually
// rendered, so a theme overriding the property, or declaring it in a relative
// unit that grows with the browser's text size, needs no parsing here to be
// reported correctly.
//
// .header-guest is excluded because the guest layout — public shares, error
// pages, the sign-in form — styles its header differently, and its height is
// not the one the app's own windows are laid out against. A page carrying no
// header at all reports nothing, which leaves the last known height in place:
// the right outcome, that page having no header to center within either.
//
// Only the main frame reports. Every bundled script is installed with
// forMainFrameOnly: false, and an embedded editor's iframe has no header of the
// app's window to describe.

(function () {
  if (window !== window.top) {
    return;
  }

  var lastReportedHeight = null;

  function reportHeight() {
    var header = document.querySelector("#header:not(.header-guest)");

    if (!header) {
      return;
    }

    var height = Math.round(header.getBoundingClientRect().height);

    if (height === lastReportedHeight) {
      return;
    }

    lastReportedHeight = height;

    window.webkit.messageHandlers.headerHeight.postMessage({
      height: height,
    });
  }

  reportHeight();

  var header = document.querySelector("#header:not(.header-guest)");

  if (header) {
    var observer = new ResizeObserver(function () {
      reportHeight();
    });

    observer.observe(header);
  }
})();
