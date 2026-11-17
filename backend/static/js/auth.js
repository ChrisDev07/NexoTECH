/**
 * Módulo de Autenticación y Protección de Datos (Ley 1581 de 2012) de Origo
 */
window.OrigoAuth = (() => {
  let currentUser = null;
  let onAuthChange = null;

  function setError(msg) {
    const el = document.getElementById('authError');
    if (!msg) {
      el.style.display = 'none';
      el.innerText = '';
      return;
    }
    el.innerText = `⚠️ ${msg}`;
    el.style.display = 'block';
  }

  function switchAuthMode(mode) {
    setError('');
    const isRegister = mode === 'register';
    document.getElementById('authTabLogin').classList.toggle('active', !isRegister);
    document.getElementById('authTabRegister').classList.toggle('active', isRegister);
    document.getElementById('loginForm').style.display = isRegister ? 'none' : 'block';
    document.getElementById('registerForm').style.display = isRegister ? 'block' : 'none';
  }

  function applyUserToHeader(user) {
    currentUser = user;
    const authView = document.getElementById('authView');
    const appMain = document.getElementById('mainAppView');

    if (!user) {
      authView.style.display = 'flex';
      appMain.style.display = 'none';
      return;
    }

    authView.style.display = 'none';
    appMain.style.display = 'flex';
    document.getElementById('greetingName').innerText = `¡Hola, ${user.owner_name}! ☀️`;
    document.getElementById('storeSubtitle').innerText = `📍 ${user.business_name} · ${user.zone}`;
    document.getElementById('communityZoneTitle').innerText = `💰 Ahorro de la semana · ${user.zone}`;
  }

  async function init(callback) {
    onAuthChange = callback;
    const user = await window.OrigoAPI.getCurrentUser();
    applyUserToHeader(user);
    if (user && onAuthChange) {
      onAuthChange(user);
    }
  }

  async function submitLogin(e) {
    if (e) e.preventDefault();
    setError('');
    const phone = document.getElementById('loginPhone').value;
    const pin = document.getElementById('loginPin').value;
    try {
      const data = await window.OrigoAPI.login(phone, pin);
      applyUserToHeader(data.user);
      if (onAuthChange) onAuthChange(data.user);
      window.OrigoApp.showToast(`☀️ ¡Bienvenido, ${data.user.owner_name}!`);
    } catch (err) {
      setError(err.message);
    }
  }

  async function loginDemo() {
    document.getElementById('loginPhone').value = '3101234567';
    document.getElementById('loginPin').value = '1234';
    await submitLogin();
  }

  async function submitRegister(e) {
    if (e) e.preventDefault();
    setError('');
    const payload = {
      owner_name: document.getElementById('regOwner').value,
      business_name: document.getElementById('regBusiness').value,
      zone: document.getElementById('regZone').value,
      phone: document.getElementById('regPhone').value,
      pin: document.getElementById('regPin').value,
      habeas_data_accepted: document.getElementById('regHabeas').checked
    };
    try {
      const data = await window.OrigoAPI.register(payload);
      applyUserToHeader(data.user);
      if (onAuthChange) onAuthChange(data.user);
      window.OrigoApp.showToast(`🎉 ¡Tienda "${data.user.business_name}" creada con éxito!`);
    } catch (err) {
      setError(err.message);
    }
  }

  async function logout() {
    await window.OrigoAPI.logout();
    applyUserToHeader(null);
    switchAuthMode('login');
    window.OrigoApp.showToast('👋 Sesión cerrada de forma segura');
  }

  async function openPrivacyModal() {
    const policy = await window.OrigoAPI.getPrivacyPolicy();
    document.getElementById('privacyTitle').innerText = `🛡️ ${policy.title}`;
    document.getElementById('privacySummary').innerText = policy.summary;
    document.getElementById('privacyRoles').innerHTML = `
      <div><strong>Responsable:</strong> ${policy.roles.responsable}</div>
      <div style="margin-top: 6px;"><strong>Encargado:</strong> ${policy.roles.encargado}</div>
    `;
    document.getElementById('privacyRights').innerHTML = policy.rights
      .map(r => `<li style="margin-bottom: 6px;">✔ ${r}</li>`)
      .join('');
    document.getElementById('privacyModal').classList.add('open');
  }

  function closePrivacyModal() {
    document.getElementById('privacyModal').classList.remove('open');
  }

  function getUser() {
    return currentUser;
  }

  return {
    init,
    switchAuthMode,
    submitLogin,
    loginDemo,
    submitRegister,
    logout,
    openPrivacyModal,
    closePrivacyModal,
    getUser
  };
})();
