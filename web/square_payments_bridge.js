(function () {
  let squareCard = null;
  let sdkPromise = null;
  let sdkEnvironment = null;

  function result(ok, values) {
    return JSON.stringify(Object.assign({ ok: ok }, values || {}));
  }

  window.loadSquarePaymentsSdk = async function (environment) {
    const normalized = environment === 'production' ? 'production' : 'sandbox';
    if (window.Square && sdkEnvironment === normalized) return result(true);
    if (sdkPromise && sdkEnvironment === normalized) return sdkPromise;
    await window.destroySquareCard();
    sdkEnvironment = normalized;
    const url = normalized === 'production'
      ? 'https://web.squarecdn.com/v1/square.js'
      : 'https://sandbox.web.squarecdn.com/v1/square.js';
    sdkPromise = new Promise((resolve) => {
      const old = document.getElementById('ringmaster-square-sdk');
      if (old) old.remove();
      const script = document.createElement('script');
      script.id = 'ringmaster-square-sdk';
      script.src = url;
      script.onload = () => resolve(result(true));
      script.onerror = () => resolve(result(false, {
        error: 'Square payment fields could not be loaded.'
      }));
      document.head.appendChild(script);
    });
    return sdkPromise;
  };

  window.initializeSquareCard = async function (applicationId, locationId, mountElementId) {
    try {
      await window.destroySquareCard();
      if (!window.Square) return result(false, { error: 'Square Web Payments SDK is unavailable.' });
      const mount = document.getElementById(mountElementId);
      if (!mount) return result(false, { error: 'Square card form mount was not found.' });
      const payments = window.Square.payments(applicationId, locationId);
      squareCard = await payments.card();
      await squareCard.attach('#' + CSS.escape(mountElementId));
      return result(true);
    } catch (_) {
      squareCard = null;
      return result(false, { error: 'Square card fields could not be initialized.' });
    }
  };

  window.tokenizeSquareCard = async function () {
    try {
      if (!squareCard) return result(false, { error: 'Square card fields are not ready.' });
      const tokenResult = await squareCard.tokenize();
      if (tokenResult.status === 'OK' && tokenResult.token) {
        return result(true, { source_id: tokenResult.token });
      }
      const message = Array.isArray(tokenResult.errors) && tokenResult.errors.length
        ? tokenResult.errors.map((error) => error.message).filter(Boolean).join(' ')
        : 'Check the card information and try again.';
      return result(false, { error: message });
    } catch (_) {
      return result(false, { error: 'Card tokenization failed. Please try again.' });
    }
  };

  window.destroySquareCard = async function () {
    const card = squareCard;
    squareCard = null;
    if (card && typeof card.destroy === 'function') {
      try { await card.destroy(); } catch (_) { /* Already detached. */ }
    }
    return result(true);
  };
})();
