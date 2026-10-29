# Role `newt`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

- The Pangolin `newt` container must share a Docker network with any app it fronts: it proxies to them over the `newt` bridge. Newt never mounts the Docker socket either: its sidecar `newt-socket-proxy` (`ansible/roles/newt/defaults/main.yml` lists each allowed call and why) lets through only what newt 1.19.0 calls, and no inspect of other containers (their env, hence every compose's secrets). A newt bump must re-read `docker/docker.go` against that list; a missing call only empties Pangolin's container list (proxy logs a 403).
