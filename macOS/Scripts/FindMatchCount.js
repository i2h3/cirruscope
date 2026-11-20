// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Contributes findMatchCount to the Cirruscope namespace: the number of times
// the find bar's query occurs in the page's text, counted case-insensitively
// per text node. WKFindResult reports only whether a match exists and no
// total, so the Mac's find bar asks the page for the count to show next to the
// search field.
//
// Text nodes under script, style and form elements are skipped, as the
// browser's own find skips them. A match spanning an inline element boundary
// is not counted, which the browser's find would catch.
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
  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode(node) {
        return node.parentElement?.closest(skipped)
          ? NodeFilter.FILTER_REJECT
          : NodeFilter.FILTER_ACCEPT;
      },
    },
  );

  let count = 0;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const text = node.nodeValue.toLowerCase();
    let index = text.indexOf(needle);
    while (index !== -1) {
      count += 1;
      index = text.indexOf(needle, index + needle.length);
    }
  }

  return count;
};
