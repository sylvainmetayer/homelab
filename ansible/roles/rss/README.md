# Role `rss`

FreshRSS (`rss`, Docker VM), read in the browser only: API off except for
Homepage's widget, Karakeep Button extension (comments in `defaults/main.yml`
and `tasks/main.yml`). App description: `docs/apps.md`.

## Disk writes

FreshRSS was the Docker VM's top disk writer (~24 GB in 68 h, 2026-11-01,
`docs/conventions/resource-limits.md` « Disk I/O »): one SQLite database per
user (`data/users/<user>/db.sqlite`, ~330 MB, 846 feeds), in rollback-journal
mode with `synchronous=FULL`. The role sets three things:

- **Refresh delay** `rss_ttl_default` (3 h; FreshRSS's default is 1 h): the
  `ttl_default` key of each `data/users/<user>/config.php`, set by `replace`
  as the role does for `api_enabled` (inserted when the file has none). A UI
  change of the default (Configuration > Archivage) is undone by the next
  deploy; a feed with its own TTL (Configuration > Flux) keeps it, at most
  once an hour. With the hourly cron, a feed is skipped while
  `now <= lastUpdate + TTL` (no margin) and its last update ended seconds
  after the previous run started: 3 h exactly refreshes each feed every
  **4 h** (a TTL just under 3 h, e.g. 10500, for a real 3 h).
- **Cron hourly** (`CRON_MIN=17` in the compose): FreshRSS 1.30 compares a
  feed's TTL with its last *successful* update (`feedController.php`,
  `actualizeFeeds`), so a feed in error is retried, and its `error` column
  written, at every cron run whatever its TTL. Every 15 min that was 166 feeds
  in error × 4 per hour. The cleanup of those feeds is Sylvain's (UI), not the
  role's.
- **WAL**: each `db.sqlite` is switched once with
  `PRAGMA journal_mode=WAL`, kept in the file header (FreshRSS sets no journal
  mode of its own). A commit then appends to `db.sqlite-wal` instead of
  creating, fsyncing and deleting a `-journal` file, and readers (the web UI)
  no longer block the refresh. Trade-offs: two more files next to the
  database (`-wal`, `-shm`, owned by www-data; the `-wal` grows up to
  ~4 MB between checkpoints, more during a long read), all on one host only
  (no NFS); a copy of `db.sqlite` alone, without its `-wal`, may miss the last
  commits. Backups are unaffected: the borgmatic template copies a WAL database
  with `VACUUM INTO` (one read transaction, never blocking FreshRSS) and
  excludes the live `db.sqlite`, `-wal`, `-shm` and `-journal`
  (`ansible/roles/borgmatic/README.md`); `.backup`, its fallback for a
  rollback-journal database, starts over at each write of FreshRSS. To go back:
  `sqlite3 db.sqlite 'PRAGMA journal_mode=DELETE'`, app stopped, and drop the
  WAL tasks.

Measure the container's writes (two reads ~15 min apart, a full cron cycle,
outside borgmatic's 00:30-03:00 window; from `ansible/`):

```bash
mise exec -- ansible docker -o -m shell -a 'id=$(docker ps -q --no-trunc -f name=^rss$); date +%s; grep "^254:0" /sys/fs/cgroup/system.slice/docker-$id.scope/io.stat'
```

The write rate is the `wbytes` (and `wios`) difference over the `date`
difference. Before this change (2026-11-02 07:32-07:4x): see the PR.
