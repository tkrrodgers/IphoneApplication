/* Voice for the simulator: Web Speech API.
   - Wake mode: continuous listening for "Hi Herb" / "Hey Herb" (+ optional command in the same breath)
   - Push-to-talk: one utterance
   - HERB speaks with speechSynthesis; the mic pauses while HERB talks so it doesn't hear itself.
   Edge/Chrome send recognition audio to their cloud speech service; the real app uses on-device speech. */
(function () {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const WAKE = /\b(?:hi|hey|hay|high|hello|okay|ok|yo)[\s,.!]*(?:herb|herbs|herve|erb|urb|her b|burb|curb|herbie)\b[\s,.!]*/i;
  const V = {
    supported: !!SR, ttsSupported: 'speechSynthesis' in window,
    wakeOn: false, mode: 'idle',          // idle | wake | command | ptt
    speaking: false, voice: null, rate: 1.05, speakOn: true,
    onCommand: () => {}, onState: () => {}, onHeard: () => {}, onWake: () => {},
  };
  let rec = null, commandTimer = null, restartTimer = null, lastWakeAt = 0;

  function store(k, v) { try { localStorage.setItem('herb.' + k, v); } catch (e) { /* storage unavailable */ } }
  function load(k) { try { return localStorage.getItem('herb.' + k); } catch (e) { return null; } }

  function setMode(m) { V.mode = m; V.onState(); }

  function chime(up = true) {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = 'sine'; o.frequency.setValueAtTime(up ? 660 : 880, ctx.currentTime);
      o.frequency.linearRampToValueAtTime(up ? 990 : 550, ctx.currentTime + 0.14);
      g.gain.setValueAtTime(0.0001, ctx.currentTime); g.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.22);
      o.connect(g).connect(ctx.destination); o.start(); o.stop(ctx.currentTime + 0.25);
      setTimeout(() => ctx.close(), 400);
    } catch (e) { /* audio unavailable */ }
  }

  function stopRec() {
    clearTimeout(restartTimer);
    if (rec) { rec.onend = null; rec.onresult = null; rec.onerror = null; try { rec.abort(); } catch (e) {} rec = null; }
  }

  function makeRec(continuous) {
    const r = new SR();
    r.lang = 'en-US'; r.continuous = continuous; r.interimResults = true; r.maxAlternatives = 1;
    r.onerror = e => {
      if (e.error === 'no-speech' || e.error === 'aborted') return;
      const msg = { 'not-allowed': 'Microphone permission was blocked. Allow the mic for this page (lock icon in the address bar).',
        'service-not-allowed': 'Speech recognition isn\'t allowed in this browser window. Open the simulator in Microsoft Edge or Google Chrome.',
        network: 'The browser\'s speech service couldn\'t be reached. Check the internet connection, or use Edge/Chrome.',
        'audio-capture': 'No microphone was found.' }[e.error] || ('Speech error: ' + e.error);
      V.lastError = msg; V.onHeard('⚠ ' + msg);
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed' || e.error === 'audio-capture') { V.wakeOn = false; setMode('idle'); }
    };
    return r;
  }

  // ---------- wake mode ----------
  function startWake() {
    if (!V.supported || V.speaking) return;
    stopRec();
    rec = makeRec(true);
    rec.onresult = e => {
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const res = e.results[i], text = res[0].transcript.trim();
        V.onHeard(text + (res.isFinal ? '' : '…'));
        if (V.mode === 'command') {                          // capturing the command after "Hi Herb"
          V.onInterim && V.onInterim(text.replace(WAKE, ''));
          if (res.isFinal && text.replace(WAKE, '').trim().length > 1) { finishCommand(text.replace(WAKE, '').trim()); return; }
          continue;
        }
        const m = text.match(WAKE);
        if (m && Date.now() - lastWakeAt > 1500) {
          const rest = text.slice(m.index + m[0].length).trim();
          if (res.isFinal && rest.length > 3) { lastWakeAt = Date.now(); chime(true); V.onWake(); finishCommand(rest); return; }
          if (!res.isFinal) continue;                          // wait to see if a command follows
          lastWakeAt = Date.now(); chime(true); V.onWake();
          setMode('command');
          clearTimeout(commandTimer);
          commandTimer = setTimeout(() => { if (V.mode === 'command') { chime(false); setMode('wake'); } }, 8000);
        }
      }
    };
    rec.onend = () => { rec = null; if (V.wakeOn && !V.speaking) restartTimer = setTimeout(startWake, 250); else if (V.mode !== 'ptt') setMode('idle'); };
    try { rec.start(); setMode(V.mode === 'command' ? 'command' : 'wake'); } catch (e) { restartTimer = setTimeout(startWake, 600); }
  }

  function finishCommand(text) {
    clearTimeout(commandTimer);
    setMode(V.wakeOn ? 'wake' : 'idle');
    V.onCommand(text, { voice: true });
  }

  // ---------- push to talk ----------
  V.listenOnce = function () {
    if (!V.supported) { V.onHeard('⚠ This browser can\'t do speech recognition. Open http://localhost:8765 in Edge or Chrome, or type to HERB.'); return; }
    V.stopSpeaking();
    stopRec();
    rec = makeRec(false);
    let finalText = '';
    rec.onresult = e => {
      let interim = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        if (e.results[i].isFinal) finalText += e.results[i][0].transcript; else interim += e.results[i][0].transcript;
      }
      const shown = (finalText + ' ' + interim).trim();
      V.onHeard(shown); V.onInterim && V.onInterim(shown.replace(WAKE, ''));
    };
    rec.onend = () => {
      rec = null; setMode('idle');
      const t = finalText.replace(WAKE, '').trim();
      if (t) V.onCommand(t, { voice: true }); else V.onInterim && V.onInterim('');
      if (V.wakeOn) restartTimer = setTimeout(startWake, 300);
    };
    try { rec.start(); chime(true); setMode('ptt'); } catch (e) { setMode('idle'); }
  };
  V.cancelListen = function () { stopRec(); setMode('idle'); if (V.wakeOn) startWake(); };

  // HERB just asked a question: take the next thing said as the answer — no "Hi Herb" needed — for a few seconds
  V.awaitReply = function (ms = 9000) {
    if (!V.wakeOn) return;
    chime(true);
    setMode('command');
    clearTimeout(commandTimer);
    commandTimer = setTimeout(() => { if (V.mode === 'command') { chime(false); setMode('wake'); } }, ms);
    clearTimeout(restartTimer);
    if (!rec && !V.speaking) startWake();
  };

  V.setWake = function (on) {
    V.wakeOn = on && V.supported;
    if (V.wakeOn) startWake(); else { stopRec(); setMode('idle'); }
  };

  // ---------- speech out ----------
  function pickVoice() {
    const vs = speechSynthesis.getVoices();
    const saved = load('voice');
    return vs.find(v => v.name === saved) ||
      vs.find(v => /en-US/i.test(v.lang) && /natural/i.test(v.name) && /(andrew|guy|christopher|brian|eric|davis)/i.test(v.name)) ||
      vs.find(v => /en-US/i.test(v.lang) && /natural/i.test(v.name)) ||
      vs.find(v => /en-US/i.test(v.lang) && /(david|mark|guy)/i.test(v.name)) ||
      vs.find(v => /^en/i.test(v.lang)) || vs[0] || null;
  }
  V.voices = () => (V.ttsSupported ? speechSynthesis.getVoices().filter(v => /^en/i.test(v.lang)) : []);
  V.setVoice = name => { V.voice = V.voices().find(v => v.name === name) || V.voice; store('voice', name); };
  V.setRate = r => { V.rate = r; store('rate', r); };

  V.speak = function (text) {
    return new Promise(resolve => {
      if (!V.ttsSupported || !V.speakOn || !text) return resolve();
      speechSynthesis.cancel();
      const clean = String(text).replace(/[*_#•·]/g, ' ').replace(/\s+/g, ' ').replace(/(\d),(\d{3})/g, '$1$2');
      const u = new SpeechSynthesisUtterance(clean);
      u.voice = V.voice || pickVoice(); u.rate = V.rate; u.pitch = 1;
      const wasWake = V.wakeOn;
      stopRec();                                   // don't let HERB hear itself
      V.speaking = true; V.onState();
      const done = () => { V.speaking = false; V.onState(); if (wasWake && V.wakeOn) restartTimer = setTimeout(startWake, 350); resolve(); };
      u.onend = done; u.onerror = done;
      speechSynthesis.speak(u);
      // Safety net: some engines never fire onend
      setTimeout(() => { if (V.speaking && !speechSynthesis.speaking) done(); }, Math.max(4000, clean.length * 90));
    });
  };
  V.stopSpeaking = () => { if (V.ttsSupported) speechSynthesis.cancel(); V.speaking = false; V.onState(); };

  V.init = function () {
    const r = parseFloat(load('rate')); if (r) V.rate = r;
    if (V.ttsSupported) {
      const set = () => { V.voice = pickVoice(); V.onState(); };
      set(); speechSynthesis.onvoiceschanged = set;
    }
  };

  // Electron-based panes expose webkitSpeechRecognition but can't reach the speech service
  V.likelyEmbedded = /Electron|Claude/i.test(navigator.userAgent);
  window.V = V;
})();
