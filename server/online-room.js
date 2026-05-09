#!/usr/bin/env node
const http = require("http");
const { createReadStream, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } = require("fs");
const { randomBytes } = require("crypto");
const path = require("path");
const { URL } = require("url");

const ROOT = path.resolve(__dirname, "..");
const STATE_DIR = path.join(ROOT, "dist");
const STATE_FILE = path.join(STATE_DIR, "room-state.json");
const PORT = Number(process.env.PORT || 8787);
const ROOM_SECRET = process.env.ROOM_SECRET || randomBytes(5).toString("hex");
const MAX_EVENTS = 240;
const ACTIONS = new Set(["pat", "feed", "walk", "miss", "nap", "visit", "remind", "message"]);
const ACTION_LABELS = {
  pat: "摸摸",
  feed: "投喂",
  walk: "遛弯",
  miss: "想你",
  nap: "休息",
  visit: "串门",
  remind: "提醒",
  message: "文字",
};

let nextEventID = loadNextEventID();
let nextReceiptID = Date.now();
let events = [];
let receipts = [];
let streams = new Set();

function loadNextEventID() {
  try {
    const state = JSON.parse(readFileSync(STATE_FILE, "utf8"));
    const saved = Number(state.nextEventID || 0);
    return Math.max(saved, Date.now());
  } catch {
    return Date.now();
  }
}

function saveNextEventID() {
  try {
    mkdirSync(STATE_DIR, { recursive: true });
    writeFileSync(STATE_FILE, JSON.stringify({ nextEventID }, null, 2) + "\n");
  } catch {
    // Best-effort persistence; the room still works if the state file cannot be written.
  }
}

function send(res, status, body, headers = {}) {
  const isString = typeof body === "string";
  res.writeHead(status, {
    "Content-Type": isString ? "text/html; charset=utf-8" : "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...headers,
  });
  res.end(isString ? body : JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 32) {
        reject(new Error("body too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

function hasRoomAccess(url) {
  return url.searchParams.get("room") === ROOM_SECRET || url.searchParams.get("desktop") === "1";
}

function addEvent(event) {
  const item = {
    id: nextEventID++,
    at: Date.now(),
    kind: event.action === "message" ? "message" : "action",
    action: event.action,
    actor: event.actor || "好友",
    petName: event.petName || `${event.actor || "好友"}的小狗`,
    petKind: event.petKind || "cockapoo",
    source: event.source || "web",
    label: ACTION_LABELS[event.action] || event.action,
    text: event.text || "",
    readBy: [],
  };
  events.push(item);
  saveNextEventID();
  if (events.length > MAX_EVENTS) {
    events = events.slice(-MAX_EVENTS);
  }

  broadcast(item);
  return item;
}

function broadcast(item) {
  const data = `data: ${JSON.stringify(item)}\n\n`;
  for (const stream of streams) {
    stream.write(data);
  }
}

function markRead(eventID, reader, readerSource) {
  const event = events.find((item) => item.id === eventID);
  if (!event || event.source === readerSource) return null;
  const source = readerSource || "reader";
  if (event.readBy.some((item) => item.source === source)) {
    return { ok: true, duplicate: true, event };
  }
  const read = {
    id: nextReceiptID++,
    kind: "read",
    eventId: event.id,
    eventLabel: event.label,
    eventAction: event.action,
    eventSource: event.source,
    reader: reader || "对方",
    readerSource: source,
    at: Date.now(),
  };
  event.readBy.push({
    reader: read.reader,
    source,
    at: read.at,
  });
  receipts.push(read);
  if (receipts.length > MAX_EVENTS) {
    receipts = receipts.slice(-MAX_EVENTS);
  }
  broadcast(read);
  return { ok: true, duplicate: false, event, read };
}

function pageHTML() {
  return `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>卷毛联机房间</title>
    <style>
      :root {
        color-scheme: light;
        --room-dog-scale: 1;
        --ink: #242832;
        --muted: #66707d;
        --line: rgba(38, 48, 64, 0.14);
        --pink: #ff5c91;
        --blue: #4d78d9;
        --gold: #d4a23a;
        --green: #79bf93;
        --lavender: #8c73d7;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        color: var(--ink);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
        background:
          linear-gradient(120deg, rgba(255,255,255,0.72), rgba(255,255,255,0.38)),
          radial-gradient(circle at 20% 10%, #ffd8e7, transparent 34%),
          radial-gradient(circle at 86% 18%, #d6ecff, transparent 30%),
          linear-gradient(180deg, #f6fbff, #fff7f9 62%, #f2fbf4);
      }
      main {
        display: grid;
        grid-template-columns: minmax(280px, 410px) minmax(300px, 1fr);
        gap: 22px;
        width: min(1080px, calc(100vw - 32px));
        min-height: 100vh;
        margin: 0 auto;
        padding: 28px 0;
        align-items: center;
      }
      .pet-side, .panel {
        border: 1px solid var(--line);
        border-radius: 14px;
        background: rgba(255,255,255,0.78);
        box-shadow: 0 24px 70px rgba(65, 78, 104, 0.15);
        backdrop-filter: blur(18px);
      }
      .pet-side {
        min-height: 620px;
        display: grid;
        place-items: center;
        padding: 26px;
      }
      .pet-stage {
        position: relative;
        width: 260px;
        height: 330px;
        display: grid;
        place-items: center;
      }
      .bubble {
        position: absolute;
        top: 18px;
        left: 50%;
        transform: translateX(-50%);
        min-width: 126px;
        max-width: 230px;
        padding: 10px 13px;
        border: 1px solid var(--line);
        border-radius: 10px;
        background: white;
        text-align: center;
        font-weight: 800;
        box-shadow: 0 12px 28px rgba(43, 54, 72, 0.12);
      }
      .bubble::after {
        content: "";
        position: absolute;
        left: calc(50% - 7px);
        bottom: -7px;
        width: 12px;
        height: 12px;
        background: white;
        border-right: 1px solid var(--line);
        border-bottom: 1px solid var(--line);
        transform: rotate(45deg);
      }
      .dog {
        position: relative;
        width: 192px;
        height: 208px;
        margin-top: 68px;
        transform: scale(var(--room-dog-scale));
        transform-origin: center bottom;
        background-image: url("/assets/coco-spritesheet.webp");
        background-repeat: no-repeat;
        background-size: 1536px 1872px;
        image-rendering: auto;
        filter: drop-shadow(0 18px 12px rgba(46, 58, 39, 0.18));
        animation: idle 1.8s steps(6) infinite;
      }
      .dog[data-action="pat"] { animation: wave 0.9s steps(4) infinite; background-position-y: -624px; }
      .dog[data-action="feed"] { animation: jump 0.8s steps(5) infinite; background-position-y: -832px; }
      .dog[data-action="walk"] { animation: run 0.65s steps(8) infinite; background-position-y: -208px; }
      .dog[data-action="nap"] { animation: none; background-position: -960px -1040px; }
      .dog[data-action="miss"] { animation: wave 0.9s steps(4) infinite; background-position-y: -624px; }
      .dog[data-action="remind"] { animation: run 0.65s steps(8) infinite; background-position-y: -208px; }
      .hearts {
        position: absolute;
        inset: 0;
        pointer-events: none;
      }
      .heart {
        position: absolute;
        left: 50%;
        bottom: 116px;
        color: var(--pink);
        font-size: 28px;
        font-weight: 900;
        opacity: 0;
        animation: heart 1.45s ease-out forwards;
      }
      .heart:nth-child(2) { margin-left: -55px; animation-delay: 0.08s; font-size: 24px; }
      .heart:nth-child(3) { margin-left: 42px; animation-delay: 0.16s; font-size: 22px; }
      .heart:nth-child(4) { margin-left: 8px; animation-delay: 0.28s; font-size: 32px; }
      .panel {
        padding: 28px;
      }
      h1 {
        margin: 0 0 8px;
        font-size: 30px;
        line-height: 1.15;
        letter-spacing: 0;
      }
      .sub {
        margin: 0 0 22px;
        color: var(--muted);
        line-height: 1.6;
      }
      .status {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 18px;
        padding: 8px 11px;
        border: 1px solid var(--line);
        border-radius: 999px;
        background: white;
        color: var(--muted);
        font-size: 13px;
        font-weight: 800;
      }
      .dot {
        width: 9px;
        height: 9px;
        border-radius: 50%;
        background: var(--gold);
      }
      .status[data-live="true"] .dot { background: var(--green); }
      .pet-choice {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 8px;
        margin: 0 0 16px;
      }
      .pet-choice button {
        min-height: 42px;
        border-radius: 999px;
      }
      .pet-choice button[aria-pressed="true"] {
        border-color: rgba(255, 92, 145, 0.42);
        background: #fff1f6;
        color: #b91f52;
      }
      input {
        flex: 1;
        min-width: 0;
        height: 42px;
        border: 1px solid var(--line);
        border-radius: 10px;
        padding: 0 12px;
        color: var(--ink);
        background: white;
        font: inherit;
        font-weight: 750;
      }
      .actions {
        display: grid;
        grid-template-columns: 1fr;
        gap: 8px;
        margin: 12px 0 22px;
      }
      .message-row, .scale-row {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 14px;
      }
      .message-row button, .log-tools button {
        flex: 0 0 72px;
        min-height: 42px;
      }
      .scale-row label {
        flex: 0 0 auto;
        color: var(--muted);
        font-size: 13px;
        font-weight: 850;
      }
      .scale-row input {
        height: auto;
        padding: 0;
      }
      button {
        min-height: 58px;
        border: 1px solid var(--line);
        border-radius: 11px;
        background: white;
        color: var(--ink);
        font: inherit;
        font-weight: 900;
        cursor: pointer;
        transition: transform 150ms ease, border-color 150ms ease, background 150ms ease;
      }
      button:hover {
        transform: translateY(-1px);
        border-color: rgba(77, 120, 217, 0.34);
        background: #f8fbff;
      }
      button[data-action="miss"] {
        color: #c9235a;
        background: #fff1f6;
      }
      button[data-action="visit"] {
        color: #5b43b5;
        background: #f5f1ff;
      }
      button[data-action="remind"] {
        color: #0d6d6a;
        background: #effcf9;
      }
      .log {
        display: flex;
        flex-direction: column;
        gap: 10px;
        max-height: 320px;
        overflow: auto;
        padding: 14px;
        border: 1px solid var(--line);
        border-radius: 16px;
        background:
          linear-gradient(180deg, rgba(255, 247, 250, 0.82), rgba(246, 251, 255, 0.78)),
          rgba(255,255,255,0.62);
      }
      .log-item {
        display: grid;
        align-self: flex-start;
        gap: 5px;
        max-width: 84%;
        padding: 10px 12px;
        border: 1px solid rgba(255, 92, 145, 0.14);
        border-radius: 16px 16px 16px 5px;
        background: #fff;
        color: #3b4350;
        line-height: 1.35;
        box-shadow: 0 10px 22px rgba(83, 71, 95, 0.10);
      }
      .log-item[data-own="true"] {
        align-self: flex-end;
        border-color: rgba(77, 120, 217, 0.16);
        border-radius: 16px 16px 5px 16px;
        background: #f8fbff;
      }
      .log-top {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        color: var(--muted);
        font-size: 12px;
      }
      .log-text {
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        color: #2f3946;
        font-weight: 800;
      }
      .receipt {
        color: var(--muted);
        font-size: 12px;
        font-weight: 800;
      }
      .log-tools {
        display: flex;
        gap: 10px;
        margin: -2px 0 10px;
      }
      .log-tools button {
        min-height: 36px;
        border-radius: 999px;
        font-size: 13px;
      }
      .hint {
        margin: 14px 0 0;
        color: var(--muted);
        font-size: 13px;
        line-height: 1.6;
      }
      @keyframes idle { from { background-position: 0 0; } to { background-position: -1152px 0; } }
      @keyframes wave { from { background-position-x: 0; } to { background-position-x: -768px; } }
      @keyframes jump { from { background-position-x: 0; } to { background-position-x: -960px; } }
      @keyframes run { from { background-position-x: 0; } to { background-position-x: -1536px; } }
      @keyframes heart {
        0% { opacity: 0; transform: translate(-50%, 18px) scale(0.76); }
        18% { opacity: 1; }
        100% { opacity: 0; transform: translate(-50%, -86px) scale(1.18); }
      }
      @media (max-width: 780px) {
        main { grid-template-columns: 1fr; padding: 16px 0; align-items: start; }
        .pet-side { min-height: 430px; }
        .actions { grid-template-columns: 1fr; }
      }
    </style>
  </head>
  <body>
    <main>
      <section class="pet-side">
        <div class="pet-stage">
          <div class="bubble" id="bubble">卷毛等你们联机。</div>
          <div class="dog" id="dog" data-action="idle" aria-label="卷毛"></div>
          <div class="hearts" id="hearts" aria-hidden="true"></div>
        </div>
      </section>
      <section class="panel">
        <div class="status" id="status" data-live="false"><span class="dot"></span><span id="status-text">连接中</span></div>
        <h1>卷毛联机房间</h1>
        <p class="sub">你们可以一起照顾桌面小狗，也可以让自己的狗去对方桌面串门。</p>
        <div class="pet-choice" aria-label="选择狗狗">
          <button type="button" data-pet="cockapoo" aria-pressed="false">卷毛</button>
          <button type="button" data-pet="dachshund" aria-pressed="false">叶子</button>
        </div>
        <div class="actions">
          <button type="button" data-action="pat">摸摸</button>
          <button type="button" data-action="feed">投喂</button>
          <button type="button" data-action="walk">遛弯</button>
          <button type="button" data-action="miss">想你</button>
          <button type="button" data-action="nap">休息</button>
          <button type="button" data-action="visit">串门</button>
          <button type="button" data-action="remind">提醒</button>
        </div>
        <div class="message-row">
          <input id="message" maxlength="240" placeholder="写一句话给对方" aria-label="文字消息">
          <button type="button" id="send-message">发送</button>
        </div>
        <div class="scale-row">
          <label for="dog-scale">狗狗大小</label>
          <input id="dog-scale" type="range" min="70" max="135" value="100" aria-label="狗狗大小">
        </div>
        <div class="log-tools">
          <button type="button" id="read-all">已读全部</button>
          <button type="button" id="clear-log">清除显示</button>
        </div>
        <div class="log" id="log" aria-live="polite"></div>
        <p class="hint">桌面版可以右键设置联机网址。固定域名后，把完整房间链接填进去即可。</p>
        <p class="hint">
          <a href="/downloads/juanmao-desktop.zip?room=${ROOM_SECRET}">下载卷毛 Mac 桌面版</a>
          ·
          <a href="/downloads/yezi-desktop.zip?room=${ROOM_SECRET}">下载叶子 Mac 桌面版</a>
        </p>
      </section>
    </main>
    <script>
      const params = new URLSearchParams(location.search);
      const room = params.get("room");
      const sourceKey = "juanmao-room-client-id";
      const source = localStorage.getItem(sourceKey) || "web-" + Math.random().toString(16).slice(2);
      localStorage.setItem(sourceKey, source);
      const labels = { pat: "摸摸", feed: "投喂", walk: "遛弯", miss: "想你", nap: "休息", visit: "串门", remind: "提醒", message: "文字" };
      const speech = {
        pat: "被摸摸，好开心。",
        feed: "卷毛吃到啦。",
        walk: "卷毛去散步。",
        miss: "我也想你",
        nap: "卷毛安心睡觉。",
        visit: "去串门啦。",
        remind: "喝水，起来走走。",
        message: "收到一句话。",
      };
      const dog = document.querySelector("#dog");
      const bubble = document.querySelector("#bubble");
      const hearts = document.querySelector("#hearts");
      const log = document.querySelector("#log");
      const status = document.querySelector("#status");
      const statusText = document.querySelector("#status-text");
      const messageInput = document.querySelector("#message");
      const scaleInput = document.querySelector("#dog-scale");
      const rows = new Map();
      const eventsById = new Map();
      const petButtons = [...document.querySelectorAll("[data-pet]")];
      const savedScale = localStorage.getItem("juanmao-room-dog-scale");
      if (savedScale) scaleInput.value = savedScale;
      let selectedPet = localStorage.getItem("juanmao-room-pet-kind") || "cockapoo";

      function isFriendActor() {
        return selectedPet === "dachshund";
      }

      function petNameForActor(actor) {
        return selectedPet === "dachshund" ? "叶子" : "卷毛";
      }

      function actorName() {
        return petNameForActor();
      }

      function updatePreviewPet() {
        dog.style.backgroundImage = isFriendActor()
          ? 'url("/assets/dachshund-spritesheet.webp")'
          : 'url("/assets/coco-spritesheet.webp")';
        dog.setAttribute("aria-label", isFriendActor() ? "叶子" : "卷毛");
        petButtons.forEach((button) => {
          button.setAttribute("aria-pressed", String(button.dataset.pet === selectedPet));
        });
      }

      function setLive(text, live) {
        status.dataset.live = String(Boolean(live));
        statusText.textContent = text;
      }

      function formatEvent(event) {
        if (event.action === "message") {
          return event.text || "发来一句话。";
        }
        return event.label || labels[event.action] || event.action;
      }

      function receiptText(event) {
        if (event.source !== source) {
          return (event.readBy || []).some((item) => item.source === source) ? "我已读" : "未读";
        }
        if (!event.readBy || event.readBy.length === 0) return "对方未读";
        return event.readBy.map((item) => (item.reader || "对方") + "已读").join("，");
      }

      function addLog(text) {
        const item = document.createElement("div");
        item.className = "log-item";
        item.textContent = text;
        log.append(item);
        log.scrollTop = log.scrollHeight;
      }

      function renderEvent(event) {
        const own = event.source === source;
        eventsById.set(event.id, event);
        let item = rows.get(event.id);
        if (!item) {
          item = document.createElement("div");
          item.className = "log-item";
          item.dataset.own = String(own);
          item.dataset.eventId = String(event.id);
          item.innerHTML = '<div class="log-top"><strong></strong><span class="receipt"></span></div><div class="log-text"></div>';
          rows.set(event.id, item);
          log.append(item);
          log.scrollTop = log.scrollHeight;
        }
        item.querySelector("strong").textContent = (event.actor || "好友") + "：" + (event.label || labels[event.action] || event.action);
        item.querySelector(".log-text").textContent = formatEvent(event);
        item.querySelector(".receipt").textContent = receiptText(event);
      }

      function applyReceipt(receipt) {
        const item = rows.get(receipt.eventId);
        if (item) {
          item.querySelector(".receipt").textContent = (receipt.reader || "对方") + "已读";
        }
      }

      function showHearts() {
        hearts.replaceChildren();
        for (let i = 0; i < 4; i += 1) {
          const heart = document.createElement("span");
          heart.className = "heart";
          heart.textContent = "♥";
          hearts.append(heart);
        }
      }

      function animate(action, text) {
        dog.dataset.action = action;
        bubble.textContent = text || speech[action] || "卷毛收到啦。";
        if (action === "miss" || action === "visit" || action === "remind") showHearts();
        window.clearTimeout(animate.timer);
        if (action !== "nap") {
          animate.timer = window.setTimeout(() => {
            dog.dataset.action = "idle";
          }, 1700);
        }
      }

      async function sendAction(action) {
        if (!room) {
          addLog("这个链接缺少房间码。");
          return;
        }
        const actor = actorName();
        animate(action, action === "miss" ? "我也想你" : undefined);
        const response = await fetch("/api/action?room=" + encodeURIComponent(room), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action,
            actor,
            petName: petNameForActor(actor),
            petKind: selectedPet,
            source
          })
        }).catch(() => {
          addLog("发送失败，可能是隧道断开了。");
        });
        if (response?.ok) {
          const payload = await response.json();
          renderEvent(payload.event);
        }
      }

      async function sendMessage() {
        if (!room) {
          addLog("这个链接缺少房间码。");
          return;
        }
        const text = messageInput.value.trim();
        if (!text) return;
        const actor = actorName();
        messageInput.value = "";
        bubble.textContent = text;
        const response = await fetch("/api/action?room=" + encodeURIComponent(room), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action: "message",
            actor,
            petName: petNameForActor(actor),
            petKind: selectedPet,
            text,
            source
          })
        }).catch(() => {
          addLog("发送失败，可能是隧道断开了。");
        });
        if (response?.ok) {
          const payload = await response.json();
          renderEvent(payload.event);
        }
      }

      async function markRead(event) {
        if (!event || event.source === source || (event.readBy || []).some((entry) => entry.source === source)) return;
        const actor = actorName();
        const response = await fetch("/api/read?room=" + encodeURIComponent(room), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ eventId: event.id, reader: actor, source })
        }).catch(() => null);
        if (response?.ok) {
          event.readBy = [...(event.readBy || []), { reader: actor, source, at: Date.now() }];
          renderEvent(event);
        }
      }

      async function markAllRead() {
        const unread = [...eventsById.values()].filter((event) => event.source !== source && !(event.readBy || []).some((entry) => entry.source === source));
        await Promise.all(unread.map((event) => markRead(event)));
      }

      function clearLog() {
        rows.clear();
        eventsById.clear();
        log.replaceChildren();
      }

      function startStream() {
        if (!room) {
          setLive("缺少房间码", false);
          addLog("请使用带 room 参数的完整链接。");
          return;
        }
        const stream = new EventSource("/api/stream?room=" + encodeURIComponent(room));
        stream.onopen = () => setLive("已连接", true);
        stream.onerror = () => setLive("重连中", false);
        stream.onmessage = (message) => {
          const event = JSON.parse(message.data);
          if (event.kind === "read") {
            applyReceipt(event);
            return;
          }
          renderEvent(event);
          if (event.source !== source) {
            animate(event.action, event.action === "message" ? event.text : (event.action === "miss" ? "我也想你" : speech[event.action]));
          }
        };
      }

      document.querySelectorAll("[data-action]").forEach((button) => {
        button.addEventListener("click", () => sendAction(button.dataset.action));
      });
      petButtons.forEach((button) => {
        button.addEventListener("click", () => {
          selectedPet = button.dataset.pet;
          localStorage.setItem("juanmao-room-pet-kind", selectedPet);
          updatePreviewPet();
        });
      });
      document.querySelector("#send-message").addEventListener("click", sendMessage);
      document.querySelector("#read-all").addEventListener("click", markAllRead);
      document.querySelector("#clear-log").addEventListener("click", clearLog);
      messageInput.addEventListener("keydown", (event) => {
        if (event.key === "Enter" && !event.shiftKey) {
          event.preventDefault();
          sendMessage();
        }
      });
      scaleInput.addEventListener("input", () => {
        localStorage.setItem("juanmao-room-dog-scale", scaleInput.value);
        document.documentElement.style.setProperty("--room-dog-scale", String(Number(scaleInput.value) / 100));
      });
      document.documentElement.style.setProperty("--room-dog-scale", String(Number(scaleInput.value) / 100));
      updatePreviewPet();
      startStream();
    </script>
  </body>
</html>`;
}

async function handle(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/") {
    send(res, 200, pageHTML());
    return;
  }

  if (req.method === "GET" && url.pathname === "/assets/coco-spritesheet.webp") {
    res.writeHead(200, {
      "Content-Type": "image/webp",
      "Cache-Control": "public, max-age=3600",
    });
    createReadStream(path.join(ROOT, "assets", "coco-spritesheet.webp")).pipe(res);
    return;
  }

  if (req.method === "GET" && url.pathname === "/assets/dachshund-spritesheet.webp") {
    res.writeHead(200, {
      "Content-Type": "image/webp",
      "Cache-Control": "public, max-age=3600",
    });
    createReadStream(path.join(ROOT, "assets", "dachshund-spritesheet.webp")).pipe(res);
    return;
  }

  if (req.method === "GET" && ["/downloads/yezi-desktop.zip", "/downloads/juanmao-desktop.zip"].includes(url.pathname)) {
    if (!hasRoomAccess(url)) {
      send(res, 403, { ok: false, error: "bad room" });
      return;
    }
    const fileName = url.pathname.endsWith("juanmao-desktop.zip")
      ? "juanmao-desktop.zip"
      : "yezi-desktop.zip";
    const file = path.join(ROOT, "dist", "release", fileName);
    if (!existsSync(file)) {
      send(res, 404, { ok: false, error: "app zip not ready" });
      return;
    }
    const stat = statSync(file);
    res.writeHead(200, {
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="${fileName}"`,
      "Content-Length": stat.size,
      "Cache-Control": "no-store",
    });
    createReadStream(file).pipe(res);
    return;
  }

  if (url.pathname === "/api/events" && req.method === "GET") {
    if (!hasRoomAccess(url)) {
      send(res, 403, { ok: false, error: "bad room" });
      return;
    }
    const since = Number(url.searchParams.get("since") || 0);
    const sinceReceipt = Number(url.searchParams.get("sinceReceipt") || 0);
    const client = url.searchParams.get("client") || "";
    const items = events.filter((event) => event.id > since && event.source !== client);
    const readItems = receipts.filter((receipt) => receipt.id > sinceReceipt && receipt.eventSource === client);
    send(res, 200, { ok: true, events: items, receipts: readItems });
    return;
  }

  if (url.pathname === "/api/stream" && req.method === "GET") {
    if (!hasRoomAccess(url)) {
      send(res, 403, { ok: false, error: "bad room" });
      return;
    }
    res.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-store",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    res.write(`event: ready\ndata: ${JSON.stringify({ ok: true })}\n\n`);
    streams.add(res);
    req.on("close", () => streams.delete(res));
    return;
  }

  if (url.pathname === "/api/action" && req.method === "POST") {
    if (!hasRoomAccess(url)) {
      send(res, 403, { ok: false, error: "bad room" });
      return;
    }
    let payload = {};
    try {
      const raw = await readBody(req);
      payload = raw ? JSON.parse(raw) : {};
    } catch {
      send(res, 400, { ok: false, error: "bad json" });
      return;
    }
    const action = String(payload.action || "");
    if (!ACTIONS.has(action)) {
      send(res, 400, { ok: false, error: "bad action" });
      return;
    }
    const text = String(payload.text || "").trim().slice(0, 240);
    if (action === "message" && !text) {
      send(res, 400, { ok: false, error: "empty message" });
      return;
    }
    const event = addEvent({
      action,
      actor: String(payload.actor || "好友").slice(0, 18),
      petName: String(payload.petName || `${payload.actor || "好友"}的小狗`).slice(0, 18),
      petKind: String(payload.petKind || "cockapoo").slice(0, 24),
      source: String(payload.source || "web").slice(0, 80),
      text,
    });
    send(res, 200, { ok: true, event });
    return;
  }

  if (url.pathname === "/api/read" && req.method === "POST") {
    if (!hasRoomAccess(url)) {
      send(res, 403, { ok: false, error: "bad room" });
      return;
    }
    let payload = {};
    try {
      const raw = await readBody(req);
      payload = raw ? JSON.parse(raw) : {};
    } catch {
      send(res, 400, { ok: false, error: "bad json" });
      return;
    }
    const result = markRead(
      Number(payload.eventId || 0),
      String(payload.reader || "对方").slice(0, 18),
      String(payload.source || "web").slice(0, 80)
    );
    if (!result) {
      send(res, 404, { ok: false, error: "event not found" });
      return;
    }
    send(res, 200, result);
    return;
  }

  if (url.pathname === "/api/config" && req.method === "GET") {
    send(res, 200, { ok: true, room: ROOM_SECRET, port: PORT });
    return;
  }

  send(res, 404, { ok: false, error: "not found" });
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((error) => {
    console.error(error);
    send(res, 500, { ok: false, error: "server error" });
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Juanmao room server running on http://127.0.0.1:${PORT}/?room=${ROOM_SECRET}`);
  console.log(`ROOM_SECRET=${ROOM_SECRET}`);
});
