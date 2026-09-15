// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Reports whether Nextcloud's sidebar toggle is present and expanded through
// the `sidebarToggleState` message handler, both once on injection and on every
// subsequent DOM mutation that could change either value.

(() => {
  function reportState() {
    const element = document.querySelector(".app-navigation-toggle");
    const available = !!element;
    const expanded =
      available && element.getAttribute("aria-expanded") === "true";
    window.webkit.messageHandlers.sidebarToggleState.postMessage({
      available: available,
      expanded: expanded,
    });
  }

  reportState();

  const observer = new MutationObserver(() => {
    reportState();
  });

  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["aria-expanded", "class"],
  });
})();
