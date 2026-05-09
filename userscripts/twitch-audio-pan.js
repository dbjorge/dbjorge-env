// ==UserScript==
// @name     Twitch Audio Pan
// @version  1
// @grant    none
// @include  https://www.twitch.tv/*
// ==/UserScript==

// Based on https://stackoverflow.com/a/63193575

const PAN_LEFT = -1;
const PAN_CENTER = 0;
const PAN_RIGHT = 1;

function buttonText(pan) {
  return (
  	pan === PAN_LEFT ? '🔊 L' :
  	pan === PAN_CENTER ? '🔊 C' :
    pan === PAN_RIGHT ? '🔊 R' :
    `🔊 ${pan}`);
};

const AudioContext = window.AudioContext || window.webkitAudioContext;
const audioContext = new AudioContext();
const stereoPannerNode = new StereoPannerNode(audioContext, { pan: PAN_CENTER });
const alreadyInstalledElements = [];
const allMenuButtons = [];
const numExpectedMenuContainers = 2;

function installStereoPannerNode() {
	const targetElements = document.querySelectorAll('audio,video');

  for (const targetElement of targetElements) {
    if (alreadyInstalledElements.includes(targetElement)) { continue; }

    const track = audioContext.createMediaElementSource(targetElement);
    track.connect(stereoPannerNode).connect(audioContext.destination);
    alreadyInstalledElements.push(targetElement);
  }
}
  
let currentPan = PAN_CENTER;

// pan goes from -1 (100% left) to 1 (100% right)
function setAudioPan(pan) {
  installStereoPannerNode();
  stereoPannerNode.pan.value = pan;
  currentPan = pan;
  
  for (const menuButton of allMenuButtons) {
    menuButton.innerText = buttonText(pan);
  }    
}

function onMenuButtonClick() {
  newPan =
  	currentPan === PAN_LEFT ? PAN_CENTER :
  	currentPan === PAN_CENTER ? PAN_RIGHT :
    currentPan === PAN_RIGHT ? PAN_LEFT :
  	PAN_CENTER;
  
  console.log(`Switching audio pan from ${currentPan} (${buttonText(currentPan)}) to ${newPan} (${buttonText(newPan)})`);
 
  setAudioPan(newPan);
}

function makeMenuButton() {
  const menuItem = document.createElement('button');
  menuItem.classList.add('audioPanUserScriptMenuButton');
  menuItem.setAttribute('style', 'display:flex; height:100%; width:40px; color:white; align-items: center;');
  menuItem.innerText = buttonText(PAN_CENTER);
  menuItem.addEventListener('click', onMenuButtonClick);
  
  allMenuButtons.push(menuItem);

  return menuItem;
}


const menuItemInstaller = setInterval(() => {
  const menuContainers = document.querySelectorAll('.player-controls__left-control-group')
  for (menuContainer of menuContainers) {
    if (menuContainer.querySelector('.audioPanUserScriptMenuButton') == null) {
      const menuButton = makeMenuButton();
      menuContainer.appendChild(menuButton);
      
      if (allMenuButtons.length >= numExpectedMenuContainers) {
        clearInterval(menuItemInstaller);
      	console.log(`Audio pan button initialized`);
      }      
    }
  }
}, 100);
