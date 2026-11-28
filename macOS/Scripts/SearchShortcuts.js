// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Offers ⌘K (the server's unified search) and ⌘F (the current app's own
// search) to the page when a text field has focus, which is when the page's
// own hotkey handling ignores them because the keystroke's target is an
// editable control — and macOS otherwise only plays the alert sound (issue
// #153).
//
// The listener is registered on `window` in the bubble phase at document
// start, before the page's own scripts attach theirs, so a handler on the
// focused element is offered the keystroke first and wins when it prevents
// the default. A keystroke is claimed only when its target is an editable
// control and nothing has prevented it yet; anything else is left untouched,
// so an unfocused ⌘F still reaches the menu bar's Find… item as before.
// Claimed keystrokes are stopped and re-dispatched synthetically on `body`,
// which the page's handlers treat like a keystroke pressed with nothing
// focused — `document` itself would be ignored as a non-element target.
// Only trusted events are claimed; the synthetic re-dispatch is not, so the
// listener does not loop on it.
//
// The synthetic event copies `code`, `location`, `keyCode` and `which` from
// the original, because handlers keyed on those legacy fields would
// otherwise decline it. The original event is preventDefaulted only when the
// re-dispatch was handled or the script acts itself, so a keystroke nobody
// claims still falls through to the menu bar — a user-assigned server-app
// shortcut for ⌘K, say.
//
// ⌘F is special in one way: once the page has handled a re-dispatched ⌘F,
// its search field holds focus, and a further ⌘F aimed at that field belongs
// to the app's own find bar, exactly as when the page declines a keystroke
// whose target is an editable. Such a repeated ⌘F, like one the page
// declines outright, is reported through the `findPanel` message handler so
// the host shows the find bar. A ⌘K clears that state, so the sequence
// ⌘K → ⌘F offers the page's search first.

(() => {
  // The element the page's own search focused after the last handled ⌘F, or
  // null. The page focuses its search box in a later tick, so the element is
  // read after the dispatch, in a timeout.
  let engagedElement = null;

  // Mirrors the editable check in the page's own hotkey guard.
  const isEditable = (target) =>
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLSelectElement ||
    (target instanceof HTMLElement && target.isContentEditable);

  const isEngaged = (target) =>
    engagedElement?.isConnected &&
    (target === engagedElement || engagedElement.contains(target));

  window.addEventListener("keydown", (event) => {
    if (!event.isTrusted) {
      return;
    }

    // Exactly Command and nothing else: Control, Option and Shift all disqualify.
    if (!event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) {
      return;
    }

    const key = event.key?.toLowerCase();

    if (key !== "k" && key !== "f") {
      return;
    }

    const target = event.composedPath()[0] ?? event.target;

    // Only a keystroke aimed at an editable control needs rescuing; anything
    // else is left to the page and the menu bar untouched, and a handler that
    // already prevented the default wins.
    if (!isEditable(target) || event.defaultPrevented) {
      return;
    }

    event.stopImmediatePropagation();

    if (key === "k") {
      // A fresh ⌘K re-engages the page's unified search, so a following ⌘F is
      // offered to the page again rather than straight to the find bar.
      engagedElement = null;
    }

    if (key === "f" && isEngaged(target)) {
      event.preventDefault();
      window.webkit.messageHandlers.findPanel.postMessage({});
      return;
    }

    const synthetic = new KeyboardEvent("keydown", {
      key,
      code: event.code,
      location: event.location,
      metaKey: true,
      repeat: event.repeat,
      bubbles: true,
      cancelable: true,
    });
    // `keyCode` and `which` are not settable through the constructor.
    Object.defineProperty(synthetic, "keyCode", { value: event.keyCode });
    Object.defineProperty(synthetic, "which", { value: event.which });

    const handled =
      (document.body ?? document.documentElement).dispatchEvent(synthetic) ===
      false;

    if (handled) {
      event.preventDefault();
    }

    if (key === "f") {
      if (handled) {
        setTimeout(() => {
          const focused = document.activeElement;
          engagedElement =
            focused &&
            focused !== document.body &&
            focused !== document.documentElement
              ? focused
              : null;
        }, 0);
      } else {
        event.preventDefault();
        window.webkit.messageHandlers.findPanel.postMessage({});
      }
    }
  });
})();
