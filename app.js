const STORAGE_KEY = "interactive-juanmao-v1";
const CELL_WIDTH = 192;
const CELL_HEIGHT = 208;

const animations = {
  idle: { row: 0, frames: 6, fps: 3 },
  runRight: { row: 1, frames: 8, fps: 11 },
  runLeft: { row: 2, frames: 8, fps: 11 },
  wave: { row: 3, frames: 4, fps: 4 },
  jump: { row: 4, frames: 5, fps: 7 },
  failed: { row: 5, frames: 8, fps: 5 },
  waiting: { row: 6, frames: 6, fps: 3 },
  running: { row: 7, frames: 6, fps: 10 },
  review: { row: 8, frames: 6, fps: 3 },
};

const phrases = {
  pat: ["好舒服。", "再摸一下。", "卷毛开心了。"],
  feed: ["吃到啦。", "小碗清空。", "今天也要乖乖吃饭。"],
  walk: ["出门小跑。", "我会跟上。", "散步路线确认。"],
  nap: ["趴一会儿。", "小睡充电。", "耳朵先休息。"],
  call: ["我回来了。", "到你身边。", "卷毛到位。"],
  review: ["陪你看。", "我认真盯着。", "这段我来守着。"],
  idle: ["卷毛在。", "尾巴轻轻晃。", "今天也陪你。"],
  drag: ["换个地方。", "这里也不错。"],
};

const pet = document.querySelector("#pet");
const sprite = document.querySelector("#sprite");
const speech = document.querySelector("#speech");
const mood = document.querySelector("#mood");
const floatLayer = document.querySelector("#float-layer");
const meters = {
  love: document.querySelector("#love-meter"),
  fullness: document.querySelector("#fullness-meter"),
  energy: document.querySelector("#energy-meter"),
};

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const pick = (items) => items[Math.floor(Math.random() * items.length)];

let data = loadData();
let activeAnimation = "idle";
let frame = 0;
let lastFrameAt = 0;
let speechTimer = 0;
let animationTimer = 0;
let movementTimer = 0;
let wanderTimer = 0;
let tongueTimer = 0;
let drag = null;

function loadData() {
  const defaults = {
    x: Math.round(window.innerWidth * 0.46),
    y: Math.round(window.innerHeight * 0.42),
    stats: {
      love: 62,
      fullness: 72,
      energy: 76,
    },
    lastSeen: Date.now(),
  };

  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (!saved || typeof saved !== "object") return defaults;
    const elapsedHours = Math.max(0, (Date.now() - Number(saved.lastSeen || Date.now())) / 36e5);
    const stats = saved.stats || defaults.stats;
    return {
      x: Number.isFinite(saved.x) ? saved.x : defaults.x,
      y: Number.isFinite(saved.y) ? saved.y : defaults.y,
      stats: {
        love: clamp(Math.round((stats.love ?? defaults.stats.love) - elapsedHours * 0.4), 35, 100),
        fullness: clamp(Math.round((stats.fullness ?? defaults.stats.fullness) - elapsedHours * 2.2), 18, 100),
        energy: clamp(Math.round((stats.energy ?? defaults.stats.energy) + elapsedHours * 3.4), 25, 100),
      },
      lastSeen: Date.now(),
    };
  } catch {
    return defaults;
  }
}

function saveData() {
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({
      ...data,
      lastSeen: Date.now(),
    })
  );
}

function bounds() {
  const bottomReserve = window.innerWidth < 760 ? 176 : 128;
  return {
    maxX: Math.max(8, window.innerWidth - pet.offsetWidth - 10),
    maxY: Math.max(8, window.innerHeight - pet.offsetHeight - bottomReserve),
  };
}

function place(x = data.x, y = data.y) {
  const { maxX, maxY } = bounds();
  data.x = clamp(Math.round(x), 8, maxX);
  data.y = clamp(Math.round(y), 92, maxY);
  pet.style.left = `${data.x}px`;
  pet.style.top = `${data.y}px`;
  saveData();
}

function updateMeters() {
  Object.entries(data.stats).forEach(([key, value]) => {
    meters[key].value = value;
  });

  let text = "尾巴轻轻晃着。";
  if (data.stats.fullness < 32) text = "卷毛在惦记小零食。";
  if (data.stats.energy < 34) text = "卷毛有点困了。";
  if (data.stats.love > 84) text = "卷毛正贴着你待机。";
  mood.textContent = text;
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
  if (duration > 0) {
    animationTimer = window.setTimeout(() => setAnimation(next), duration);
  }
}

function tick(timestamp) {
  const cfg = animations[activeAnimation];
  if (!lastFrameAt) lastFrameAt = timestamp;
  const frameTime = 1000 / cfg.fps;
  if (timestamp - lastFrameAt >= frameTime) {
    frame = (frame + 1) % cfg.frames;
    lastFrameAt = timestamp;
    renderFrame();
  }
  window.requestAnimationFrame(tick);
}

function say(kind, explicitText) {
  const text = explicitText || pick(phrases[kind] || phrases.idle);
  speech.textContent = text;
  pet.dataset.speaking = "true";
  clearTimeout(speechTimer);
  speechTimer = window.setTimeout(() => {
    pet.dataset.speaking = "false";
  }, 2400);
}

function pop(text) {
  const item = document.createElement("span");
  item.className = "float-pop";
  item.textContent = text;
  floatLayer.append(item);
  window.setTimeout(() => item.remove(), 920);
}

function scheduleWander() {
  clearTimeout(wanderTimer);
  if (activeAnimation === "review" || activeAnimation === "failed") return;
  wanderTimer = window.setTimeout(() => {
    if (drag || data.stats.energy < 22) return;
    const { maxX, maxY } = bounds();
    const nextX = clamp(data.x + Math.random() * 180 - 90, 8, maxX);
    const nextY = clamp(data.y + Math.random() * 74 - 37, 100, maxY);
    moveTo(nextX, nextY, 920, "idle", false, () => scheduleWander());
  }, 7000 + Math.random() * 5000);
}

function moveTo(nextX, nextY, duration = 900, finalAnimation = "idle", speak = false, done) {
  clearTimeout(wanderTimer);
  clearTimeout(movementTimer);
  clearTimeout(animationTimer);
  const { maxX, maxY } = bounds();
  const x = clamp(nextX, 8, maxX);
  const y = clamp(nextY, 92, maxY);
  const direction = x >= data.x ? "runRight" : "runLeft";

  if (speak) say("walk");
  setAnimation(direction);
  pet.style.transition = `left ${duration}ms linear, top ${duration}ms linear`;
  place(x, y);

  movementTimer = window.setTimeout(() => {
    pet.style.transition = "";
    setAnimation(finalAnimation);
    if (done) done();
  }, duration + 30);
}

function walkRoute(steps = 5) {
  clearTimeout(wanderTimer);
  clearTimeout(movementTimer);
  say("walk");
  nudgeStats({ love: 5, fullness: -5, energy: -9 });
  pop("遛弯");

  const step = (remaining) => {
    if (remaining <= 0) {
      setAnimation("wave", 1100);
      say("walk", "散步完成。");
      scheduleWander();
      return;
    }

    const { maxX, maxY } = bounds();
    const padding = 22;
    const nextX = padding + Math.random() * Math.max(40, maxX - padding * 2);
    const nextY = 120 + Math.random() * Math.max(40, maxY - 120);
    const duration = 760 + Math.random() * 420;

    moveTo(nextX, nextY, duration, "running", false, () => {
      movementTimer = window.setTimeout(() => step(remaining - 1), 110);
    });
  };

  step(steps);
}

function pat() {
  clearTimeout(wanderTimer);
  say("pat");
  showTongue();
  pop("亲密 +8");
  nudgeStats({ love: 8, energy: 1 });
  setAnimation("jump", 920);
  scheduleWander();
}

function showTongue() {
  pet.dataset.tongue = "true";
  clearTimeout(tongueTimer);
  tongueTimer = window.setTimeout(() => {
    pet.dataset.tongue = "false";
  }, 1250);
}

function feed() {
  clearTimeout(wanderTimer);
  say("feed");
  pop("饱腹 +16");
  nudgeStats({ love: 4, fullness: 16, energy: 2 });
  setAnimation("jump", 980);
  scheduleWander();
}

function nap() {
  clearTimeout(wanderTimer);
  clearTimeout(movementTimer);
  pet.style.transition = "";
  say("nap");
  pop("精力 +12");
  nudgeStats({ energy: 12, fullness: -2 });
  setAnimation("waiting");
}

function callHome() {
  const targetX = Math.round(window.innerWidth * 0.5 - pet.offsetWidth / 2);
  const targetY = Math.round(window.innerHeight * 0.48);
  say("call");
  nudgeStats({ love: 3 });
  moveTo(targetX, targetY, 850, "wave", false, () => {
    setAnimation("wave", 1200);
    scheduleWander();
  });
}

function reviewTogether() {
  clearTimeout(wanderTimer);
  clearTimeout(movementTimer);
  pet.style.transition = "";
  say("review");
  pop("陪读");
  nudgeStats({ love: 3, energy: -2 });
  setAnimation("review");
}

function startDrag(event) {
  drag = {
    id: event.pointerId,
    offsetX: event.clientX - data.x,
    offsetY: event.clientY - data.y,
    startX: event.clientX,
    startY: event.clientY,
    moved: false,
  };
  clearTimeout(wanderTimer);
  clearTimeout(movementTimer);
  clearTimeout(animationTimer);
  pet.setPointerCapture(event.pointerId);
  pet.style.transition = "";
  setAnimation("waiting");
}

function moveDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  const dx = Math.abs(event.clientX - drag.startX);
  const dy = Math.abs(event.clientY - drag.startY);
  drag.moved = drag.moved || dx > 4 || dy > 4;
  place(event.clientX - drag.offsetX, event.clientY - drag.offsetY);
}

function endDrag(event) {
  if (!drag || drag.id !== event.pointerId) return;
  pet.releasePointerCapture(event.pointerId);
  const wasMoved = drag.moved;
  drag = null;
  if (wasMoved) {
    say("drag");
    nudgeStats({ love: 1 });
    setAnimation("idle");
    scheduleWander();
  } else {
    pat();
  }
}

function handleAction(action) {
  if (action === "pat") pat();
  if (action === "feed") feed();
  if (action === "walk") walkRoute();
  if (action === "nap") nap();
  if (action === "call") callHome();
  if (action === "review") reviewTogether();
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => handleAction(button.dataset.action));
});

pet.addEventListener("pointerdown", startDrag);
pet.addEventListener("pointermove", moveDrag);
pet.addEventListener("pointerup", endDrag);
pet.addEventListener("pointercancel", endDrag);
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
scheduleWander();
