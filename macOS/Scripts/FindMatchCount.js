// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Contributes findMatchCount to the Cirruscope namespace: the number of times
// the find bar's query occurs in the page's text, counted case-insensitively
// per text node. WKFindResult reports only whether a match exists and no
// total, so the Mac's find bar asks the page for the count to show next to the
// search field.
//
// Text nodes under script, style and form elements are skipped, as the
// browser's own find skips them, and so are text nodes in hidden elements
// (display: none, the hidden attribute, visibility: hidden), which
// checkVisibility reports. The values of visible text controls (text-like
// inputs and textareas) are counted instead, because the browser's own find
// searches them; other input types (checkbox, radio, password, date, submit)
// are not. The walk also enters rendered same-origin iframes and open shadow
// roots, which the browser's own find searches; closed shadow roots,
// cross-origin frames and frames in hidden elements stay uncounted. A match
// spanning an inline element boundary is not counted, which the browser's own
// find would catch.
//
// The namespace is assigned idempotently, because the script is evaluated again
// for every find and may meet a namespace another script already created.

window.Cirruscope = window.Cirruscope || {};

window.Cirruscope.findMatchCount = (query) => {
  if (!query || !document.body) {
    return 0;
  }

  const needle = query.toLowerCase();
  const skipped = "script,style,noscript,template,textarea,input,select";
  const textControlTypes = [
    "text",
    "search",
    "url",
    "tel",
    "email",
    "number",
    "textarea",
  ];

  let count = 0;
  const countIn = (text) => {
    const haystack = text.toLowerCase();
    let index = haystack.indexOf(needle);
    while (index !== -1) {
      count += 1;
      index = haystack.indexOf(needle, index + needle.length);
    }
  };

  const countInRoot = (root) => {
    if (!root) {
      return;
    }

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        // Text placed directly in a shadow root has no parentElement; its host stands in.
        const parent = node.parentElement ?? node.parentNode?.host;
        if (parent?.closest(skipped)) {
          return NodeFilter.FILTER_REJECT;
        }
        if (!parent?.checkVisibility({ visibilityProperty: true })) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });

    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      countIn(node.nodeValue);
    }

    for (const field of root.querySelectorAll("input, textarea")) {
      if (
        textControlTypes.includes(field.type) &&
        field.checkVisibility({ visibilityProperty: true })
      ) {
        countIn(field.value || "");
      }
    }

    for (const frame of root.querySelectorAll("iframe")) {
      // WebKit's find skips a frame whose element is not rendered; a cross-origin frame has no contentDocument.
      if (frame.checkVisibility()) {
        countInRoot(frame.contentDocument?.body);
      }
    }

    for (const element of root.querySelectorAll("*")) {
      if (element.shadowRoot) {
        countInRoot(element.shadowRoot);
      }
    }
  };

  countInRoot(document.body);

  return count;
};
