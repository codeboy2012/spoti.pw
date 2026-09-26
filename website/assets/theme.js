/* ==========================================================================
   PwEevee — theme applier
   ==========================================================================
   This file exists for one reason: to apply an EXPLICIT theme choice before the
   first paint, so a visitor whose stored choice disagrees with their device does
   not see the other theme flash first.

   It is deliberately tiny and deliberately NOT deferred: it is loaded as a
   blocking <script src> in <head>, which runs before the body renders. It is a
   separate same-origin file rather than an inline script because the site ships
   a strict Content-Security-Policy with no 'unsafe-inline'.

   Everything else about theming is CSS:
     - no stored choice      -> prefers-color-scheme decides
     - no preference either  -> the bare :root block, which is DARK
   So with JavaScript disabled the site still themes itself correctly. The only
   thing lost is the ability to override the device.

   The interactive control lives in pweevee.js. This file only reads.
   ========================================================================== */
(function () {
  'use strict';

  var root = document.documentElement;

  // Lets CSS reveal controls that would do nothing without a script. Set here
  // rather than in pweevee.js so the nav does not reflow once it loads.
  root.classList.add('js');

  try {
    var choice = window.localStorage.getItem('pweevee-theme');
    // Anything other than these two means "follow the device", which is the
    // absence of the attribute. A stale or hand-edited value is ignored.
    if (choice === 'light' || choice === 'dark') {
      root.setAttribute('data-theme', choice);
    }
  } catch (e) {
    /* storage can throw in private mode or with cookies blocked; falling back
       to prefers-color-scheme is the correct behaviour, so there is nothing to
       report and nothing to retry. */
  }
}());
