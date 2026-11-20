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
// (display: none, the hidden attribute), which checkVisibility reports for the
// nearest box past display: contents, and visibility: hidden, which the text's
// parent's computed visibility decides; an unslotted child of a shadow host
// and a slot's fallback text with assigned nodes are not rendered either.
// The values and placeholders of visible text controls (text-like inputs and
// textareas) are counted instead, because the browser's own find searches them;
// other input types (checkbox, radio, password, date, submit) are not. The
// walk also enters rendered same-origin iframes and open shadow roots, which
// the browser's own find searches; closed shadow roots, cross-origin frames
// and frames in hidden elements stay uncounted. A match spanning an inline
// element boundary is not counted, which the browser's own find would catch.
// Comparison follows WebKit's case-insensitive find: typographic quotes count
// as plain ones, a no-break space as a space, and an unaccented query letter
// matches its accented forms; letters that are their own letter in a language's
// search rules, like ñ on a Mac set to Spanish, still count as their
// unaccented form, and ß does not match ss.
//
// The namespace is assigned idempotently, because the script is evaluated again
// for every find and may meet a namespace another script already created.

window.Cirruscope = window.Cirruscope || {};

window.Cirruscope.findMatchCount = (query) => {
  if (!query || !document.body) {
    return 0;
  }

  // WebKit's case-insensitive find treats typographic quotes as plain ones and a no-break space as a space, and an unaccented query letter matches its accented forms.
  const fold = (text) =>
    text
      .normalize("NFD")
      .replace(/[‘’‚‛‹›׳＇]/g, "'")
      .replace(/[“”„‟«»״＂]/g, '"')
      .replace(/\u00A0/g, " ");
  const pattern = new RegExp(
    (fold(query).match(/\P{M}\p{M}*/gu) ?? [])
      .map(
        (character) =>
          character.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
          (/\p{M}/u.test(character) ? "" : "\\p{M}*"),
      )
      .join(""),
    "giu",
  );
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
    count += (fold(text).match(pattern) ?? []).length;
  };

  const countInRoot = (root) => {
    if (!root) {
      return;
    }

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (fold(node.nodeValue).search(pattern) === -1) {
          return NodeFilter.FILTER_REJECT;
        }
        // Text placed directly in a shadow root has no parentElement; its host stands in.
        const parent = node.parentElement ?? node.parentNode?.host;
        if (parent?.closest(skipped)) {
          return NodeFilter.FILTER_REJECT;
        }
        // An unslotted child of a shadow host is not rendered, nor is a slot's fallback text once nodes are assigned to the slot.
        if (
          (node.parentElement?.shadowRoot && !node.assignedSlot) ||
          (parent?.localName === "slot" && parent.assignedNodes().length > 0)
        ) {
          return NodeFilter.FILTER_REJECT;
        }
        // checkVisibility is false for display: contents, whose text still renders, so judge the nearest box.
        let box = parent;
        while (box && getComputedStyle(box).display === "contents") {
          box = box.parentElement ?? box.parentNode?.host;
        }
        // The box decides whether the text is rendered; the text's visibility is its parent's.
        if (
          !box?.checkVisibility() ||
          getComputedStyle(parent).visibility !== "visible"
        ) {
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
        countIn(field.value || field.placeholder);
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
