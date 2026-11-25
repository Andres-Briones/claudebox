---
name: serve-web-app
description: Use when the user needs to open something running inside a claudebox container from their browser or host — starting a dev server, previewing a web app or dashboard, exposing a port, "I can't reach localhost", or running a VM whose port must be reachable. Covers published ports, the 0.0.0.0 bind, what to do when no port was published, and which exposure options need the user's OK.
---

# Serving web apps from a claudebox slot

The user's browser can only reach ports published when the slot started
(`claudebox --port 8080`, or `--port 3000:8080` to map host 3000 to slot
8080). Those ports are listed in `$CLAUDEBOX_PUBLISHED_PORTS`. They're bound
to `127.0.0.1` on the host and are the only inbound ports the slot firewall
allows.


- **Listen on `0.0.0.0`.** Dev servers often default to `127.0.0.1`, which
  can't be reached from outside the slot (`npm run dev -- --host 0.0.0.0`,
  `flask run --host 0.0.0.0`, `uvicorn --host 0.0.0.0`). Use a port from
  `$CLAUDEBOX_PUBLISHED_PORTS` and give the user the host-side URL.
- **No published port?** Ports can't be added to a running slot. Tell the
  user to relaunch with `claudebox --port <N>`, or for a one-off, to run a
  relay on the host. The relay only works if the slot was started with
  `--disable-firewall`; `hostname -I` gives the slot's IP:
  `docker run --rm -p 127.0.0.1:<N>:<N> alpine/socat TCP-LISTEN:<N>,fork,reuseaddr TCP:<slot-ip>:<N>`
- **Don't widen exposure on your own.** Don't suggest binding to `0.0.0.0`
  on the host (LAN exposure, bypasses ufw), `--disable-firewall`, or tunnel
  services (ngrok, cloudflared) without stating the risk and getting the
  user's OK. Turn off debug consoles (e.g. Flask's debugger, which is remote
  code execution) on anything the user will open.
- **VMs:** `/dev/kvm` isn't passed in, so QEMU would run fully emulated and
  be very slow. Prefer writing the VM config (Vagrantfile, cloud-init) for
  the user to run on the host. If a VM must run in the slot, forward its
  port to a published one (`-nic user,hostfwd=tcp::<N>-:80`).
