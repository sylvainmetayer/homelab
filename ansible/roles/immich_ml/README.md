# Role `immich_ml`

Immich's machine learning (face recognition, smart search, OCR) on the NAS,
with OpenVINO on the N100's iGPU, under `dc@immich_ml` (system unit, `nas.yml`,
run by hand only). Immich itself stays on the Pi (role `immich`): its server
calls this container first over the LAN, and its own `immich-machine-learning`
container stays as the fallback when the NAS is off.

- Port `3003` on the NAS's LAN IP (`immich_ml_bind_address`, `ansible_host`).
  The API has no authentication: never a Pangolin resource. UGOS's firewall
  lets the LAN in today (`b-ugos-fw` in the QG): when it is tightened, allow
  the Pi (`192.168.1.96`) to `3003`.
- The whole `/dev/dri`, `c 189:* rmw` and the render device's group, as in
  Immich's `hwaccel.ml.yml` (`openvino` service), without `/dev/bus/usb`.
  The container stays root (owner of the device), with `cap_drop: ALL` and
  `no-new-privileges`.
- Models are downloaded from Hugging Face on first use into the `model-cache`
  volume: nothing to back up.
- `mem_limit` is provisional (2x the Pi's ML peak); measure after a week.

## Turning it on (once, by hand)

1. `ansible-playbook nas.yml --tags immich_ml` (from `ansible/`).
2. From the Pi: `curl -fsS http://192.168.1.137:3003/ping` answers `pong`.
3. Immich, Administration → Settings → Machine Learning → URL: add
   `http://192.168.1.137:3003` **above** `http://immich-machine-learning:3003`
   (Immich tries the URLs in order and falls back to the next one), save.
4. Check: Administration → Jobs → Smart Search, run « Missing » on a few
   photos; `docker logs immich_machine_learning` on the NAS shows the model
   loaded with `OpenVINOExecutionProvider`, and the NAS's iGPU busy
   (`intel_gpu_top` if present, or Beszel's CPU staying low).

Back to the Pi only: remove the NAS URL in the same settings, then
`systemctl stop dc@immich_ml` on the NAS (or `remove-app`).

## Upgrades

The image must keep the same version as the Pi's `immich-server`
(`.github/scripts/check_immich_versions.py` fails the Lint otherwise), and
Renovate bumps both in the `immich-role-dependencies` group. The merge only
deploys the Pi: **run `ansible-playbook nas.yml --tags immich_ml` right after
merging an Immich bump**, or the NAS keeps the old version. Until then the
server would talk to a machine learning of another version.
