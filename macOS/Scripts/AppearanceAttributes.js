// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Mirrors the account's appearance settings, the app's effective accent color, and
// the host window's own chrome onto <html>: the two settings as the data attributes
// Cirruscope.css scopes its translucency and full-width rules to, the accent color
// as the --cirruscope-accent-color custom property the stylesheet re-derives
// Nextcloud's whole primary color family from, and the window button clearance as
// --cirruscope-window-button-clearance, which is what insets the header past the
// macOS traffic lights. Unlike the other bundled scripts this one runs nothing on
// its own: it contributes applyAppearanceAttributes to the Cirruscope namespace,
// and WebViewController calls it with the current values — both as a
// document-start user script and live via evaluateJavaScript when a setting, the
// macOS appearance, the accent-color preference, or the window's fullscreen state
// changes.
//
// The clearance rides along here rather than arriving through a script of its own
// because correctness rests on the publication schedule, and there is exactly one
// of those: every path that re-applies the appearance already re-applies this too,
// so the two cannot get out of step. It is the one value here that is a fact about
// a single window rather than about the account or the system, which is why
// WebViewController resolves it from view.window and the fullscreen transitions
// push it per window rather than broadcasting it.
//
// The namespace is assigned rather than declared, and assigned idempotently, because
// this script is re-evaluated at the top level of a page that already has one: a
// second `const` there would throw and take the whole injection down, while a
// property assignment simply rebinds. It is also why the values are passed as
// arguments rather than interpolated into the script's text — they cross as numbers
// and strings the page never parses as anything else.
//
// data-cirruscope-accent is what the stylesheet gates its accent rules on, rather
// than the presence of the custom property, which CSS cannot test for: a var()
// reference to an unset custom property is invalid at computed-value time, so
// --color-primary-element would compute to nothing at all and every primary button
// on the page would lose its color instead of keeping Nextcloud's own. accentColor
// is null when Swift could not express the color in sRGB, and the attribute then
// reads "false" so the server's theme stays untouched. windowButtonClearance is
// null whenever Swift cannot answer yet — before the view is in a window, above all
// — and the property is then removed rather than set, so the stylesheet's own
// fallback stays in force instead of a guess.
//
// The attributes go on <html> deliberately. Nextcloud puts its own data-theme-*
// attributes on <body> and rewrites them as the user switches themes, so <html> is
// the one element in the document nothing on the page competes for.

window.Cirruscope = window.Cirruscope || {};

window.Cirruscope.applyAppearanceAttributes = (
  translucency,
  fullWidth,
  accentColor,
  accentIsBright,
  windowButtonClearance,
) => {
  const root = document.documentElement;
  root.setAttribute("data-cirruscope-translucency", translucency);
  root.setAttribute("data-cirruscope-full-width", fullWidth);
  root.setAttribute("data-cirruscope-accent", accentColor ? "true" : "false");
  root.setAttribute("data-cirruscope-accent-bright", accentIsBright);

  if (accentColor) {
    root.style.setProperty("--cirruscope-accent-color", accentColor);
  } else {
    root.style.removeProperty("--cirruscope-accent-color");
  }

  if (windowButtonClearance === null) {
    root.style.removeProperty("--cirruscope-window-button-clearance");
  } else {
    root.style.setProperty(
      "--cirruscope-window-button-clearance",
      `${windowButtonClearance}px`,
    );
  }
};
