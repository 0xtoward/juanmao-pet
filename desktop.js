const STORAGE_KEY = "interactive-juanmao-desktop-v1";
const CELL_WIDTH = 192;
const CELL_HEIGHT = 208;

const animations = {
  idle: { row: 0, frames: 6, fps: 3 },
  runRight: { row: 1, frames: 8, fps: 11 },
  runLeft: { row: 2, frames: 8, fps: 11 },
  wave: { row: 3, frames: 4, fps: 4 },
  jump: { row: 4, frames: 5, fps: 7 },
  waiting: { row: 6, frames: 6, fps: 3 },
  running: { row: 7, frames: 6, fps: 10 },
};

const phrases = {
  idle: ["卷毛在。", "桌面巡逻。", "陪你工作。"],
  pat: ["好舒服。", "再摸一下。", "卷毛开心。"],
  feed: ["吃到啦。", "小碗清空。", "能量补满。"],
  walk: ["出门小跑。", "遛弯开始。", "跟着你走。"],
  nap: ["趴一会儿。", "小睡充电。", "耳朵休息。"],
};

const pet = document.querySelector("#pet");
const sprite = document.querySelector("#sprite");
const speech = document.querySelector("#speech");
const floatLayer = document.querySelector("#float-layer");
const handle = document.querySelector("#handle");
const meters = {
  love: document.querySelector("#love-meter"),
  fullness: document.querySelector("#fullness-meter"),
  energy: document.querySelector("#energy-meter"),
};

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const pick = (items) => items[Math.floor(Math.random() * items.length)];
const native = (message) => {
  if (window.webkit?.messageHandlers?.cocoNative) {
    window.webkit.messageHandlers.cocoNative.postMessage(message);
  }
};

let data = loadData();
let activeAnimation = "idle";
let frame = 0;
let lastFrameAt = 0;
let animationTimer = 0;
let movementTimer = 0;
let speechTimer = 0;
let tongueTimer = 0;
let drag = null;

function loadData() {
  const defaults = {
    x: 96,
    y: 44,
    stats: { love: 62, fullness: 72, energy: 76 },
  };
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (!saved || typeof saved !== "object") return defaults;
    return {
      x: Number.isFinite(saved.x) ? saved.x : defaults.x,
      y: Number.isFinite(saved.y) ? saved.y : defaults.y,
      stats: {
        love: clamp(saved.stats?.love ?? defaults.stats.love, 0, 100),
        fullness: clamp(saved.stats?.fullness ?? defaults.stats.fullness, 0, 100),
        energy: clamp(saved.stats?.energy ?? defaults.stats.energy, 0, 100),
      },
    };
  } catch {
    return defaults;
  }
}

function saveData() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
}

function bounds() {
  return {
    maxX: Math.max(8, window.innerWidth - pet.offsetWidth - 12),
    maxY: Math.max(36, window.innerHeight - pet.offsetHeight - 112),
  };
}

function place(x = data.x, y = data.y) {
  const { maxX, maxY } = bounds();
  data.x = clamp(Math.round(x), 8, maxX);
  data.y = clamp(Math.round(y), 24, maxY);
  pet.style.setProperty("--pet-x", `${data.x}px`);
  pet.style.setProperty("--pet-y", `${data.y}px`);
  saveData();
}

function updateMeters() {
  Object.entries(data.stats).forEach(([key, value]) => {
    meters[key].value = value;
  });
  saveData();
}

function nudgeStats(delta) {
  Object.entries(delta).forEach(([key, value]) => {
    data.stats[key] = clamp(Math.round(data.stats[key] + value), 0, 100);
  });
  updateMeters();
}

function renderFrame() {
  const cfg = animations[activeAnimation];
  sprite.style.backgroundPosition = `${-frame * CELL_WIDTH}px ${-cfg.row * CELL_HEIGHT}px`;
}

function setAnimation(name, duration = 0, next = "idle") {
  if (!animations[name]) return;
  activeAnimation = name;
  frame = 0;
  lastFrameAt = 0;
  renderFrame();
  clearTimeout(animationTimer);
  if (duration) animationTimer = window.setTimeout(() => setAnimation(next), duration);
}

function tick(timestamp) {
  const cfg = animations[activeAnimation];
  if (!lastFrameAt) lastFrameAt = timestamp;
  if (timestamp - lastFrameAt >= 1000 / cfg.fps) {
    frame = (frame + 1) % cfg.frames;
    lastFrameAt = timestamp;
    renderFrame();
  }
  window.requestAnimationFrame(tick);
}

function say(kind, explicitText) {
  speech.textContent = explicitText || pick(phrases[kind] || phrases.idle);
  pet.dataset.speaking = "true";
  clearTimeout(speechTimer);
  speechTimer = window.setTimeout(() => {
    pet.dataset.speaking = "false";
  }, 2200);
}

function pop(text) {
  const item = document.createElement("span");
  item.className = "float-pop";
  item.textContent = text;
  floatLayer.append(item);
  window.setTimeout(() => item.remove(), 920);
}

function moveTo(nextX, nextY, duration = 800, finalAnimation = "idle", done) {
  clearTimeout(movementTimer);
  clearTimeout(animationTimer);
  const direction = nextX >= data.x ? "runRight" : "runLeft";
  setAnimation(direction);
  pet.style.transition = `left ${duration}ms linear, top ${duration}ms linear`;
  place(nextX, nextY);
  movementTimer = window.setTimeout(() => {
    pet.style.transition = "";
    setAnimation(finalAnimation);
    if (done) done();
  }, duration + 30);
}

function pat() {
  say("pat");
  showTongue();
  pop("亲密 +8");
  nudgeStats({ love: 8, energy: 1 });
  setAnimation("jump", 900);
}

function showTongue() {
  pet.dataset.tongue = "true";
  clearTimeout(tongueTimer);
  tongueTimer = window.setTimeout(() => {
    pet.dataset.tongue = "false";
  }, 1250);
}

function feed() {
  say("feed");
  pop("饱腹 +16");
  nudgeStats({ love: 4, fullness: 16, energy: 2 });
  setAnimation("jump", 980);
}

function walk() {
  say("walk");
  pop("遛弯");
  nudgeStats({ love: 5, fullness: -5, energy: -9 });
  let remaining = 9;
  const step = () => {
    if (remaining <= 0) {
      setAnimation("wave", 1100);
      say("walk", "散步回来啦。");
      return;
    }
    remaining -= 1;
    const { maxX, maxY } = bounds();
    moveTo(8 + Math.random() * maxX, 34 + Math.random() * (maxY - 24), 860, "running", step);
  };
  step();
}

function nap() {
  say("nap");
  pop("精力 +12");
  nudgeStats({ energy: 12, fullness: -2 });
  setAnimation("waiting");
}

function startPetDrag(event) {
  drag = {
    id: event.pointerId,
    offsetX: event.clientX - data.x,
    offsetY: event.clientY - data.y,
    moved: false,
  };
  clearTimeout(movementTimer);
  clearTimeout(animationTimer);
  pet.setPointerCapture(event.pointerId);
  pet.style.transition = "";
  setAnimation("waiting");
}

function movePetDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  drag.moved = true;
  place(event.clientX - drag.offsetX, event.clientY - drag.offsetY);
}

function endPetDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  pet.releasePointerCapture(event.pointerId);
  const moved = drag.moved;
  drag = null;
  if (moved) {
    say("idle", "换个位置。");
    setAnimation("idle");
  } else {
    pat();
  }
}

handle.addEventListener("pointerdown", (event) => {
  if (event.target.closest("button")) return;
  handle.setPointerCapture(event.pointerId);
  native({ type: "beginWindowDrag", screenX: event.screenX, screenY: event.screenY });
});

handle.addEventListener("pointermove", (event) => {
  if (event.buttons !== 1) return;
  native({ type: "dragWindow", screenX: event.screenX, screenY: event.screenY });
});

handle.addEventListener("pointerup", (event) => {
  handle.releasePointerCapture(event.pointerId);
  native({ type: "endWindowDrag" });
});

document.querySelector("#close-button").addEventListener("click", () => {
  native({ type: "close" });
});

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => {
    const action = button.dataset.action;
    if (action === "pat") pat();
    if (action === "feed") feed();
    if (action === "walk") walk();
    if (action === "nap") nap();
  });
});

pet.addEventListener("pointerdown", startPetDrag);
pet.addEventListener("pointermove", movePetDrag);
pet.addEventListener("pointerup", endPetDrag);
pet.addEventListener("pointercancel", endPetDrag);
pet.addEventListener("dblclick", feed);
pet.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    pat();
  }
});

window.addEventListener("resize", () => place());

place();
updateMeters();
setAnimation("idle");
say("idle");
window.requestAnimationFrame(tick);
