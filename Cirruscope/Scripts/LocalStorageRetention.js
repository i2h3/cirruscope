// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Makes clearing a storage area do nothing in the server's page, so the
// preferences Nextcloud keeps in local storage, such as the emoji picker's skin
// tone and frequently used emojis, survive a lapsed browser session.
//
// When the web view's browser session lapses, Nextcloud's own page script
// clears the page's storage before it sends the page to the sign-in form. The
// app cancels that navigation and signs the page straight back in with its app
// password, so the session continues for the same account, and only the clearing
// would remain. Every sign-out the app makes erases all website data natively,
// which is why nothing here needs to clear anything.
//
// The method is replaced on the prototype, which local and session storage
// share, so clearing session storage does nothing either; that storage ends with
// the web view anyway. Both apps install this at document start in the main
// frame alone, so every embedded frame, an office editor from another origin
// among them, keeps the method it was given.

Storage.prototype.clear = () => {
  // Keeps every item: see above.
};
