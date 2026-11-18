/**
 * Módulo API Client de Origo
 * Centraliza todas las peticiones HTTP con autenticación Bearer, no-store y respaldo offline.
 */
window.OrigoAPI = (() => {
  const TOKEN_KEY = 'origo_auth_token';

  function getToken() {
    return localStorage.getItem(TOKEN_KEY) || '';
  }

  function setToken(token) {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  }

  function authHeaders(extra = {}) {
    const token = getToken();
    const headers = { ...extra };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  }

  async function getPrivacyPolicy() {
    const res = await fetch('/api/privacy', { cache: 'no-store' });
    return res.json();
  }

  async function login(phone, pin) {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone, pin })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Error al iniciar sesión');
    setToken(data.token);
    return data;
  }

  async function register(payload) {
    const res = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Error al registrar tienda');
    setToken(data.token);
    return data;
  }

  async function getCurrentUser() {
    if (!getToken()) return null;
    const res = await fetch('/api/auth/me', {
      headers: authHeaders(),
      cache: 'no-store'
    });
    if (!res.ok) {
      setToken('');
      return null;
    }
    const data = await res.json();
    return data.user || null;
  }

  async function logout() {
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: authHeaders()
      });
    } finally {
      setToken('');
    }
  }

  async function parsePhrase(phrase) {
    const res = await fetch('/api/nlp/parse', {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ phrase })
    });
    return res.json();
  }

  async function saveMovements(items, synced) {
    const res = await fetch('/api/movements', {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ items, synced })
    });
    return res.json();
  }

  async function syncMovements() {
    const res = await fetch('/api/sync', {
      method: 'POST',
      headers: authHeaders()
    });
    return res.json();
  }

  async function getMovements() {
    const res = await fetch('/api/movements', {
      headers: authHeaders(),
      cache: 'no-store'
    });
    return res.ok ? res.json() : [];
  }

  async function getDailyStock() {
    const res = await fetch('/api/stock/daily', {
      headers: authHeaders(),
      cache: 'no-store'
    });
    if (res.ok) {
      return res.json();
    }

    // Respaldo automático
    const [stockRes, movesRes] = await Promise.all([
      fetch('/api/stock', { headers: authHeaders(), cache: 'no-store' }),
      fetch('/api/movements', { headers: authHeaders(), cache: 'no-store' })
    ]);
    const stockList = await stockRes.json();
    const movesList = movesRes.ok ? await movesRes.json() : [];

    const now = new Date();
    const startSec = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0).getTime() / 1000;
    const endSec = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999).getTime() / 1000;

    const inMap = {}, outMap = {}, countMap = {}, lastTimeMap = {};
    let totalIn = 0, totalOut = 0, totalMoves = 0;

    movesList.forEach(m => {
      if (m.timestamp >= startSec && m.timestamp <= endSec) {
        totalMoves++;
        countMap[m.product_id] = (countMap[m.product_id] || 0) + 1;
        if (!lastTimeMap[m.product_id]) {
          lastTimeMap[m.product_id] = new Date(m.timestamp * 1000).toTimeString().slice(0, 5);
        }
        if (m.type === 'IN') {
          inMap[m.product_id] = (inMap[m.product_id] || 0) + Number(m.quantity);
          totalIn += Number(m.quantity);
        } else {
          outMap[m.product_id] = (outMap[m.product_id] || 0) + Number(m.quantity);
          totalOut += Number(m.quantity);
        }
      }
    });

    const items = stockList.map(s => {
      const tIn = Number((inMap[s.product_id] || 0).toFixed(2));
      const tOut = Number((outMap[s.product_id] || 0).toFixed(2));
      return {
        ...s,
        opening_stock: Number((s.current_stock - tIn + tOut).toFixed(2)),
        today_in: tIn,
        today_out: tOut,
        has_activity_today: (countMap[s.product_id] || 0) > 0,
        last_movement_time: lastTimeMap[s.product_id] || null
      };
    });

    return {
      summary: {
        total_in_today: Number(totalIn.toFixed(2)),
        total_out_today: Number(totalOut.toFixed(2)),
        movements_count_today: totalMoves
      },
      items
    };
  }

  async function getCollectiveSummary() {
    const res = await fetch('/api/collective', {
      headers: authHeaders(),
      cache: 'no-store'
    });
    return res.json();
  }

  async function joinCollectiveOrder(quantity = 10) {
    const res = await fetch('/api/collective/join', {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ quantity })
    });
    return res.json();
  }

  async function createCustomProduct(payload) {
    const res = await fetch('/api/products', {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Error al crear producto');
    return data;
  }

  return {
    getToken,
    getPrivacyPolicy,
    login,
    register,
    getCurrentUser,
    logout,
    parsePhrase,
    saveMovements,
    syncMovements,
    getMovements,
    getDailyStock,
    getCollectiveSummary,
    joinCollectiveOrder,
    createCustomProduct
  };
})();
