// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The script every frame runs: it reports what plays, drives the transport,
/// and answers a Picture in Picture request with a gesture the app can supply.
enum MediaScript {
    nonisolated static let source = """
    (function () {
      if (window.__linenMedia) { return; }
      window.__linenMedia = true;
      const post = function (message) {
        try { window.webkit.messageHandlers.linenpip.postMessage(message); } catch (e) {}
      };
      let video = null;
      let gestureAttempts = 0;
      let muteAll = false;
      const attached = new WeakSet();
      function media() {
        return Array.prototype.slice.call(document.querySelectorAll('video, audio'));
      }
      function primary() {
        if (video && !video.isConnected) { video = null; }
        return video || media()[0] || null;
      }
      function audible(m) {
        if (m.paused || m.ended) { return false; }
        if (muteAll) { return true; }
        if (m.muted || m.volume <= 0) { return false; }
        var tracks = m.audioTracks;
        if (tracks && m.readyState >= 2 && tracks.length === 0) { return false; }
        return true;
      }
      function anyPlaying() {
        return media().some(audible);
      }
      let lastAudio = null;
      function reportAudio() {
        const playing = anyPlaying();
        if (playing === lastAudio) { return; }
        lastAudio = playing;
        post('audio:' + (playing ? 1 : 0));
      }
      let lastVideo = null;
      function reportVideo() {
        const has = media().some(function (m) { return m.videoWidth > 0; });
        if (has === lastVideo) { return; }
        lastVideo = has;
        post('video:' + (has ? 1 : 0));
      }
      let lastMeta = '';
      function posterImage() {
        if (window !== window.top) { return ''; }
        var m = primary();
        var found = (m && m.poster) || '';
        if (!found) {
          var sources = ['meta[property="og:image"]', 'meta[name="twitter:image"]', 'link[rel="image_src"]'];
          for (var i = 0; i < sources.length && !found; i += 1) {
            var node = document.querySelector(sources[i]);
            if (node) { found = node.content || node.href || ''; }
          }
        }
        if (!found) { return ''; }
        try { return new URL(found, location.href).href; } catch (e) { return ''; }
      }
      function sendMeta() {
        try {
          var m = navigator.mediaSession ? navigator.mediaSession.metadata : null;
          var art = '';
          if (m && m.artwork && m.artwork.length) {
            art = m.artwork[m.artwork.length - 1].src || '';
          }
          var guessed = !art;
          if (guessed) { art = posterImage(); }
          if (!m && !art) { return; }
          var payload = JSON.stringify({
            t: (m && m.title) || '',
            a: (m && m.artist) || '',
            al: (m && m.album) || '',
            art: art,
            g: guessed ? '1' : '0'
          });
          if (payload === lastMeta) { return; }
          lastMeta = payload;
          post('meta:' + payload);
        } catch (e) {}
      }
      function stageElement() {
        const media = primary();
        if (media) { return media; }
        let best = null;
        let bestArea = 40000;
        Array.prototype.forEach.call(document.querySelectorAll('iframe'), function (frame) {
          const box = frame.getBoundingClientRect();
          const area = box.width * box.height;
          if (area > bestArea) { bestArea = area; best = frame; }
        });
        return best;
      }
      let lastRect = '';
      function reportRect() {
        if (window !== window.top) { return; }
        const stage = stageElement();
        let payload = '';
        if (stage) {
          const box = stage.getBoundingClientRect();
          if (box.width > 0 && box.height > 0) {
            payload = JSON.stringify({
              x: Math.round(box.left),
              y: Math.round(box.top),
              w: Math.round(box.width),
              h: Math.round(box.height)
            });
          }
        }
        if (payload === lastRect) { return; }
        lastRect = payload;
        post('rect:' + payload);
      }
      function forgetReportedRect() { lastRect = ''; }
      function revealStage() {
        forgetReportedRect();
        if (window !== window.top) { return; }
        const stage = stageElement();
        if (!stage) { return; }
        const box = stage.getBoundingClientRect();
        const outside = box.top < 0 || box.left < 0 ||
          box.bottom > window.innerHeight || box.right > window.innerWidth;
        if (outside) {
          try { stage.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) {}
        }
        reportRect();
      }
      const MAX_REAL_DURATION = 1e7;
      function realDuration(m) {
        const raw = m.duration;
        return (isFinite(raw) && raw > 0 && raw < MAX_REAL_DURATION) ? raw : 0;
      }
      let durationRises = 0;
      let lastDuration = -1;
      function forgetDuration() { durationRises = 0; lastDuration = -1; }
      function stretches(m) {
        const now = m.duration;
        if (lastDuration >= 0) {
          if (now > lastDuration + 0.2) {
            durationRises = Math.min(durationRises + 1, 3);
          } else if (Math.abs(now - lastDuration) <= 0.2) {
            durationRises = Math.max(durationRises - 1, 0);
          } else {
            durationRises = 0;
          }
        }
        lastDuration = now;
        return durationRises >= 2;
      }
      function isLive(m) {
        const raw = m.duration;
        if (isNaN(raw) || raw === 0) { return false; }
        if (realDuration(m) === 0) { return true; }
        return stretches(m);
      }
      function sendState() {
        const video = primary();
        if (!video) { return; }
        if (!video.paused && !video.ended) { lastPlayedAt = performance.now(); }
        post('state:' + JSON.stringify({
          t: video.currentTime || 0,
          d: realDuration(video),
          l: isLive(video) ? 1 : 0,
          p: video.paused ? 0 : 1,
          v: video.volume,
          m: video.muted ? 1 : 0,
          w: video.videoWidth || 0
        }));
      }
      function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
      function command(data) {
        const arg = parseFloat(data.slice(data.indexOf(':') + 1));
        if (data === 'linen-reveal') {
          revealStage();
          return;
        }
        if (data === 'linen-rect') {
          forgetReportedRect();
          reportRect();
          return;
        }
        if (data === 'linen-resend') {
          lastMeta = '';
          lastAudio = null;
          lastVideo = null;
          sendMeta();
          sendState();
          reportAudio();
          reportVideo();
          return;
        }
        const video = primary();
        if (!video) { return; }
        const duration = realDuration(video);
        if (data === 'linen-play') { const p = video.play(); if (p) { p.catch(function () {}); } }
        else if (data === 'linen-pause') { video.pause(); }
        else if (data.indexOf('linen-seek:') === 0) {
          video.currentTime = clamp(video.currentTime + arg, 0, duration || video.currentTime + arg);
        } else if (data.indexOf('linen-seekto:') === 0) {
          if (duration) { video.currentTime = clamp(duration * arg, 0, duration); }
        } else if (data.indexOf('linen-seekabs:') === 0) {
          video.currentTime = clamp(arg, 0, duration || arg);
        } else if (data.indexOf('linen-volume:') === 0) {
          video.muted = arg <= 0;
          video.volume = clamp(arg, 0, 1);
        } else if (data.indexOf('linen-mute:') === 0) {
          muteAll = arg === 1;
          media().forEach(function (m) { m.muted = muteAll; });
        }
        sendState();
      }
      let armedGesture = null;
      let armedGestureExpiry = null;
      let armedAt = 0;
      let lastPlayedAt = 0;
      function playedRecently() {
        return lastPlayedAt > 0 && performance.now() - lastPlayedAt < 4000;
      }
      function gesturePoint() {
        if (window !== window.top) { return null; }
        const box = video.getBoundingClientRect();
        const candidates = [
          [box.left + box.width / 2, box.top + box.height / 2],
          [box.left + 10, box.top + 10],
          [box.left + box.width / 2, Math.max(box.top - 12, 6)],
          [10, 10],
          [window.innerWidth / 2, 8]
        ];
        for (const pair of candidates) {
          const x = pair[0];
          const y = pair[1];
          if (x < 1 || y < 1 || x >= window.innerWidth - 1 || y >= window.innerHeight - 1) { continue; }
          const found = document.elementFromPoint(x, y);
          if (found && found.tagName !== 'IFRAME' && found.tagName !== 'EMBED' && found.tagName !== 'OBJECT') {
            return { x: Math.round(x), y: Math.round(y) };
          }
        }
        return null;
      }
      const swallowed = ['pointerdown', 'pointerup', 'mousedown', 'mouseup'];
      function isOurGesture() {
        return performance.now() - armedAt < 2000;
      }
      function swallow(event) {
        if (isOurGesture()) { event.stopPropagation(); }
      }
      function disarmGesture() {
        if (armedGesture) {
          document.removeEventListener('click', armedGesture, true);
          swallowed.forEach(function (name) {
            document.removeEventListener(name, swallow, true);
          });
          armedGesture = null;
        }
        if (armedGestureExpiry) {
          clearTimeout(armedGestureExpiry);
          armedGestureExpiry = null;
        }
      }
      function armGesture(onlyWhilePlaying) {
        if (!video || video.webkitPresentationMode === 'picture-in-picture') { return; }
        if (onlyWhilePlaying && (video.ended || (video.paused && !playedRecently()))) {
          post('diag:not-playing');
          return;
        }
        if (!video.videoWidth || typeof video.webkitSetPresentationMode !== 'function') {
          post('diag:no-video');
          return;
        }
        if (gestureAttempts >= 4) { post('diag:gave-up'); gestureAttempts = 0; return; }
        gestureAttempts += 1;
        disarmGesture();
        armedAt = performance.now();
        armedGesture = function (event) {
          const ours = isOurGesture();
          disarmGesture();
          if (ours && event) {
            event.stopPropagation();
            event.preventDefault();
          }
          const wasPlaying = !video.paused || playedRecently();
          try {
            allowPiP(video);
            video.webkitSetPresentationMode('picture-in-picture');
          } catch (err) {
            post('diag:error ' + err.message);
          }
          setTimeout(function () {
            if (wasPlaying && video && video.paused) {
              const p = video.play();
              if (p) { p.catch(function () {}); }
            }
            if (video && video.webkitPresentationMode !== 'picture-in-picture') {
              armGesture(onlyWhilePlaying);
            }
            else { gestureAttempts = 0; }
          }, 700);
        };
        document.addEventListener('click', armedGesture, true);
        swallowed.forEach(function (name) {
          document.addEventListener(name, swallow, true);
        });
        armedGestureExpiry = setTimeout(function () {
          disarmGesture();
          gestureAttempts = 0;
          post('diag:gesture-expired');
        }, 10000);
        const target = gesturePoint();
        if (target) { post('pipat:' + target.x + ',' + target.y); }
        post('diag:need-gesture');
      }
      window.addEventListener('message', function (event) {
        if (event.source !== window && event.source !== window.parent) { return; }
        const data = event.data;
        if (typeof data !== 'string' || data.indexOf('linen-') !== 0) { return; }
        if (data === 'linen-pip' || data === 'linen-pip-auto') {
          gestureAttempts = 0;
          if (video && video.videoWidth) { revealStage(); }
          armGesture(data === 'linen-pip-auto');
          return;
        }
        if (data === 'linen-pip-exit') {
          disarmGesture();
          gestureAttempts = 0;
          if (video) { try { video.webkitSetPresentationMode('inline'); } catch (e) {} }
          return;
        }
        command(data);
      });
      function bind(found, asPrimary) {
        if (!found) { return; }
        if (asPrimary) { video = found; }
        if (!found.__linenBound) {
          found.__linenBound = true;
          if (muteAll) { found.muted = true; }
          ['play', 'pause', 'timeupdate', 'volumechange', 'durationchange', 'seeked', 'ended']
            .forEach(function (name) { found.addEventListener(name, sendState); });
          ['play', 'pause', 'ended', 'emptied', 'volumechange']
            .forEach(function (name) { found.addEventListener(name, reportAudio); });
          found.addEventListener('volumechange', function () {
            if (muteAll && !found.muted) {
              muteAll = false;
              post('tabunmuted');
            }
          });
          found.addEventListener('ended', function () { post('ended'); });
          found.addEventListener('webkitpresentationmodechanged', function () {
            post(found.webkitPresentationMode);
          });
        }
        sendState();
        reportAudio();
      }
      function allowPiP(v) {
        if (v.disablePictureInPicture) { v.disablePictureInPicture = false; }
        if (v.hasAttribute('disablepictureinpicture')) {
          v.removeAttribute('disablepictureinpicture');
        }
      }
      function mainVideo() {
        let best = null;
        let bestScore = 0;
        Array.prototype.forEach.call(document.querySelectorAll('video'), function (v) {
          const box = v.getBoundingClientRect();
          let score = Math.max(box.width * box.height, 1);
          if (!v.paused && !v.ended) { score *= 4; }
          if (score > bestScore) { bestScore = score; best = v; }
        });
        return best;
      }
      function scan() {
        const main = mainVideo();
        if (main && main !== video) {
          forgetDuration();
          bind(main, true);
        }
        media().forEach(function (m) {
          if (m.tagName === 'VIDEO') { allowPiP(m); }
          if (!m.__linenBound) { bind(m, false); }
        });
        sendMeta();
        reportAudio();
        reportVideo();
        reportRect();
      }
      if (window === window.top) { post('hello'); }
      scan();
      setInterval(scan, 500);
    })();
    """
}
