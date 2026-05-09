// ==UserScript==
// @name               poewiki redirect
// @description        Redirect from path of exile fandom wiki to poewiki.net
// @include            *://pathofexile.fandom.com/*
// @version            1.00
// @run-at             document-start
// @grant              none
// ==/UserScript==
     
window.location.replace("https://poewiki.net" + window.location.pathname + window.location.search);
