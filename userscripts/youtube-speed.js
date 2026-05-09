// ==UserScript==
// @name               poewiki redirect
// @description        Redirect from path of exile fandom wiki to poewiki.net
// @include            *://youtube.com/watch*
// @version            1.00
// @run-at             document-start
// @grant              none
// ==/UserScript==
     

function setVideoSpeed(playbackRate) {
    $('video').playbackRate = playbackRate
}

function installStereoPannerNode() {
	const targetElements = document.querySelectorAll('audio,video');

  for (const targetElement of targetElements) {
    if (alreadyInstalledElements.includes(targetElement)) { continue; }

    const track = audioContext.createMediaElementSource(targetElement);
    track.connect(stereoPannerNode).connect(audioContext.destination);
    alreadyInstalledElements.push(targetElement);
  }
}