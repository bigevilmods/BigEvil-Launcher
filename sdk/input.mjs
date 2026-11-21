const defaultKeys = {
  ArrowLeft: 'left', KeyA: 'left',
  ArrowRight: 'right', KeyD: 'right',
  ArrowUp: 'up', KeyW: 'up',
  ArrowDown: 'down', KeyS: 'down',
  Space: 'primary', KeyZ: 'primary',
  KeyX: 'secondary', Enter: 'start',
};

export function createInput({ surface, hud, keys = defaultKeys } = {}) {
  const keyboard = new Set();
  const pointers = new Map();
  const listeners = new AbortController();
  const signal = listeners.signal;

  function reset() {
    keyboard.clear();
    pointers.clear();
  }

  (surface ?? window).addEventListener('keydown', (event) => {
    if (event.target instanceof Element &&
        event.target.closest('input, textarea, select, [contenteditable]')) return;
    if (!Object.prototype.hasOwnProperty.call(keys, event.code)) return;
    event.preventDefault();
    keyboard.add(event.code);
  }, { signal });
  window.addEventListener('keyup', (event) => keyboard.delete(event.code), { signal });
  window.addEventListener('blur', reset, { signal });
  surface?.addEventListener('blur', reset, { signal });
  document.addEventListener('visibilitychange', reset, { signal });

  hud?.addEventListener('pointerdown', (event) => {
    const button = event.target.closest('[data-action]');
    if (!button || !hud.contains(button) || event.button !== 0) return;
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, button.dataset.action);
  }, { signal });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    hud?.addEventListener(type, (event) => pointers.delete(event.pointerId), { signal });
  }

  function read() {
    let gamepadAvailable = typeof navigator.getGamepads === 'function';
    let gamepads = [];
    if (gamepadAvailable) {
      try {
        gamepads = Array.from(navigator.getGamepads()).filter((pad) => pad?.connected);
      } catch {
        gamepadAvailable = false;
      }
    }
    const pressed = new Set([...pointers.values()]);
    for (const code of keyboard) pressed.add(keys[code]);
    for (const pad of gamepads) {
      if (pad.mapping !== 'standard') continue;
      if (pad.axes[0] < -0.25 || pad.buttons[14]?.pressed) pressed.add('left');
      if (pad.axes[0] > 0.25 || pad.buttons[15]?.pressed) pressed.add('right');
      if (pad.axes[1] < -0.25 || pad.buttons[12]?.pressed) pressed.add('up');
      if (pad.axes[1] > 0.25 || pad.buttons[13]?.pressed) pressed.add('down');
      if (pad.buttons[0]?.pressed) pressed.add('primary');
      if (pad.buttons[1]?.pressed) pressed.add('secondary');
      if (pad.buttons[9]?.pressed) pressed.add('start');
    }
    return {
      pressed,
      x: Number(pressed.has('right')) - Number(pressed.has('left')),
      y: Number(pressed.has('down')) - Number(pressed.has('up')),
      gamepadAvailable,
      gamepads,
    };
  }

  return {
    read,
    dispose() {
      listeners.abort();
      reset();
    },
  };
}
