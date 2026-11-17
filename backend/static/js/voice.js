/**
 * Módulo de Captura de Voz de Origo (Web Speech API es-CO)
 */
window.OrigoVoice = (() => {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  let recognition = null;
  let isRecording = false;
  let currentPhrase = '';
  let onFinalPhrase = null;

  function init(callback) {
    onFinalPhrase = callback;
    if (!SpeechRecognition) return;

    recognition = new SpeechRecognition();
    recognition.lang = 'es-CO';
    recognition.continuous = false;
    recognition.interimResults = true;

    recognition.onstart = () => {
      isRecording = true;
      currentPhrase = '';
      document.getElementById('micBtn').classList.add('recording');
      const status = document.getElementById('micStatus');
      status.classList.remove('error');
      status.innerText = '🔴 Escuchando... Habla ahora';
      document.getElementById('micTranscript').innerText = 'Te estoy escuchando...';
    };

    recognition.onresult = (event) => {
      let transcript = '';
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        transcript += event.results[i][0].transcript;
      }
      document.getElementById('micTranscript').innerText = `"${transcript}"`;
      currentPhrase = transcript;
    };

    recognition.onerror = (event) => {
      const status = document.getElementById('micStatus');
      const transcript = document.getElementById('micTranscript');
      status.classList.add('error');
      if (event.error === 'network') {
        status.innerText = '⚠️ Navegador bloqueó servicio de voz';
        transcript.innerHTML = 'Abre en <strong>Google Chrome</strong> para usar el dictado por voz web.';
      } else if (event.error === 'not-allowed') {
        status.innerText = '⚠️ Permiso de micrófono denegado';
        transcript.innerText = 'Activa el permiso del micrófono en la barra de direcciones.';
      } else {
        status.innerText = '⚠️ No se detectó voz. Intenta de nuevo.';
        transcript.innerText = '';
      }
    };

    recognition.onend = () => {
      isRecording = false;
      document.getElementById('micBtn').classList.remove('recording');
      if (currentPhrase && currentPhrase.trim().length > 0 && onFinalPhrase) {
        document.getElementById('micStatus').innerText = '✨ Entendido. Revisando...';
        const phraseToProcess = currentPhrase;
        setTimeout(() => {
          onFinalPhrase(phraseToProcess);
          document.getElementById('micStatus').innerText = 'Presiona para hablar';
        }, 300);
      }
    };
  }

  function toggle() {
    if (recognition) {
      if (isRecording) {
        recognition.stop();
      } else {
        try { recognition.start(); } catch (e) { console.error(e); }
      }
      return;
    }
    const status = document.getElementById('micStatus');
    status.classList.add('error');
    status.innerText = '⚠️ Tu navegador no transcribe voz web';
    document.getElementById('micTranscript').innerHTML =
      'Abre en <strong>Google Chrome</strong> para usar el micrófono en vivo.';
  }

  function clearTranscript() {
    currentPhrase = '';
    document.getElementById('micTranscript').innerText = '';
  }

  return { init, toggle, clearTranscript };
})();
