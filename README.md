# Juanmao Pet

Two tiny connected macOS desktop pets: `卷毛` and `叶子`.

The project contains:

- a local Node room server in `server/online-room.js`
- a macOS desktop pet app in `macos/CocoInteractive.swift`
- sprite assets for both pets in `assets/`
- packaging scripts in `scripts/`

## Build Both Apps

```bash
./scripts/package-release-apps.sh
```

This creates:

```text
dist/release/juanmao-desktop.zip
dist/release/yezi-desktop.zip
```

By default the packaged apps point at `http://127.0.0.1:8787` with no bundled room code. To bake in a fixed endpoint for a private build:

```bash
PUBLIC_URL="https://pet.example.com" ROOM="your-room-code" ./scripts/package-release-apps.sh
```

## Run Locally

```bash
PORT=8787 ./scripts/start-online-room.sh
```

Then open:

```text
http://127.0.0.1:8787/?room=<printed-room-code>
```

Desktop apps can also be pointed at a room from the right-click menu with `设置联机网址...`.

## Fixed Domain

The easiest fixed-domain setup is Cloudflare Tunnel. If your domain is registered elsewhere, point its nameservers to Cloudflare first, then run:

```bash
./scripts/setup-fixed-cloudflare-tunnel.sh pet.example.com
```

The script starts both LaunchAgents:

- `local.juanmao.room`
- `local.juanmao.tunnel`

It also rebuilds both app zips for that endpoint.
