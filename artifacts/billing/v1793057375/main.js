const SHARED_CONFIG = { apiEndpoint: 'https://homelab.local' };

console.log("Billing Sub-Route initialized with system endpoint:", SHARED_CONFIG.apiEndpoint);

export function renderBilling(containerId) {
  const container = document.getElementById(containerId);
  if (container) {
    container.innerHTML = `
      <div style="padding: 20px; background: #1e1e24; border-radius: 8px; color: #fff; font-family: sans-serif;">
        <h3 style="color: #4caf50; margin-top: 0;">💳 Billing Component</h3>
        <p>Status: Active</p>
        <p>Lab Build Security Context: Secure</p>
        <button style="background: #4caf50; border: none; color: white; padding: 10px 20px; border-radius: 4px; cursor: pointer;">
          Process Test Payment
        </button>
      </div>
    `;
  }
}

// Automatically attach to window for runtime micro-frontend injection
window.MFE_BILLING = { renderBilling };
