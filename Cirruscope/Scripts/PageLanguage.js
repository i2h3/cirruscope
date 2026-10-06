// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Contributes pageLanguage to the Cirruscope namespace: the language the server
// rendered the current document in, as the lang attribute of <html> carries it,
// or null. Both apps call it once a page has finished loading, so that a language
// changed in Nextcloud's personal settings, which only reloads the page, reaches
// the app list the native menus are built from.
//
// The server writes that attribute from the same language lookup that names the
// apps in its navigation, which is what makes it the right thing to compare. It
// answers only for a document the server marks with data-user on <head>, which it
// does for a signed-in user's pages. The sign-in form has no user session and is
// in the browser's language rather than the account's, so it would report a
// change that is not one; a public share's layout never carries the mark at all,
// whoever views it, and is left out with it.
//
// The namespace is assigned idempotently, because the script is evaluated again
// for every document and may meet a namespace another script already created.

window.Cirruscope = window.Cirruscope || {};

window.Cirruscope.pageLanguage = () => {
  if (!document.head?.dataset.user) {
    return null;
  }

  return document.documentElement.lang || null;
};
