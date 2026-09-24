/// Rewrites the attributes of the iframe Twitch's Player library creates. The library
/// sandboxes the frame and omits picture-in-picture, and an iOS web view will not autoplay
/// audible video inside that sandbox — the stream sat black until tapped. The frame gets the
/// same attributes as the plain embed that always autoplayed; the original `createElement`
/// is restored as soon as the player exists.
const iframeAttributes =
  `var make=document.createElement;` +
  `document.createElement=function(tag){` +
  `var el=make.apply(document,arguments);` +
  `if(String(tag).toLowerCase()==='iframe'){` +
  `var set=el.setAttribute;` +
  `el.setAttribute=function(name,value){` +
  `if(name==='sandbox'){return;}` +
  `if(name==='allow'){value='autoplay; fullscreen; picture-in-picture';}` +
  `return set.call(el,name,value);` +
  `};` +
  `}` +
  `return el;` +
  `};`;

/// The official Twitch player for one channel, wrapped so the app can drive it and follow it.
///
/// A bare player.twitch.tv iframe plays fine but tells its host nothing, so the app saw a
/// player stuck "loading", fired its stall watchdog, and reloaded a stream that was playing.
/// Twitch's Player API reports PLAYING / PAUSE / ENDED / OFFLINE; each is posted to the app's
/// `embrPlayer` script-message handler, and `window.embrPlayer` takes the app's play, pause,
/// mute and quality calls.
export function embedPage(channel: string, parent: string, muted: boolean): string {
  const options = JSON.stringify({
    channel,
    parent: [parent],
    width: '100%',
    height: '100%',
    autoplay: true,
    muted,
  });
  const script =
    `(function(){` +
    `function post(s){try{window.webkit.messageHandlers.embrPlayer.postMessage(s);}catch(e){}}` +
    `if(!window.Twitch||!Twitch.Player){post('error');return;}` +
    iframeAttributes +
    `var E=Twitch.Player;var p=new E('player',${options});` +
    `document.createElement=make;` +
    `p.addEventListener(E.PLAYING,function(){post('playing');});` +
    `p.addEventListener(E.PAUSE,function(){post('paused');});` +
    `p.addEventListener(E.ENDED,function(){post('ended');});` +
    `p.addEventListener(E.OFFLINE,function(){post('ended');});` +
    `if(E.PLAYBACK_BLOCKED){p.addEventListener(E.PLAYBACK_BLOCKED,function(){post('paused');});}` +
    `window.embrPlayer={` +
    `play:function(){p.play();},` +
    `pause:function(){p.pause();},` +
    `setMuted:function(m){p.setMuted(m);},` +
    `setQuality:function(q){if(q!=='auto'){p.setQuality(q);}}` +
    `};` +
    `})();`;
  return (
    `<!doctype html><html><head><meta charset="utf-8">` +
    `<meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no">` +
    `<style>html,body,#player{margin:0;background:#000;width:100%;height:100%;overflow:hidden}iframe{border:0}</style>` +
    `<script src="https://player.twitch.tv/js/embed/v1.js"></script></head>` +
    `<body><div id="player"></div><script>${script}</script></body></html>`
  );
}
