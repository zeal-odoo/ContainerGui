# Research: container connections

## Configuration recognition

- Decision: retain Odoo support; recognize `/app-config/app.env` only when a CLI-reported process argument explicitly references that path and its parent is one virtiofs directory mount.
- Rationale: BettaFish links this file to its dotenv input. Finding an arbitrary file or injecting variables would not prove consumption.
- Alternatives: arbitrary environment edits/recreation, migrations and credentials were rejected as outside scope.

## Nginx grammar and activation

- Decision: tokenize comments/quoted values and directives; expose each literal HTTP(S) proxy target independently; preserve scheme and URI exactly. Named upstreams, variables, Unix sockets, templates and unrecognized includes remain non-editable.
- Rationale: URI/trailing-slash semantics affect routing; envsubst can overwrite generated configuration on startup. File save is not live readiness.
- Sources: [proxy_pass](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass), [upstream](https://nginx.org/en/docs/http/ngx_http_upstream_module.html), [official image envsubst](https://github.com/nginx/docker-nginx/blob/master/entrypoint/20-envsubst-on-templates.sh).
- Alternative: edit a generic IP or install guest tools; rejected because it changes routing semantics or mutates the image.

## Single-file mounts and host safety

- Decision: directory mounts use same-directory atomic replacement. Single-file Nginx mounts are editable only when stopped/created, using the original inode, private backup, metadata/revision checks, fsync, rollback on IO failure, independent readback. Running single-file mounts remain read-only.
- Rationale: Apple Containerization shares the parent via VirtioFS and bind-mounts the file inside Linux; rename can leave a bind mount referencing the old inode. Preserving inode avoids that trap; stopped-only editing avoids partial live reads.
- Sources: [Apple FileMount](https://github.com/apple/containerization/blob/0.45.0/Sources/Containerization/FileMount.swift), [rename semantics](https://man7.org/linux/man-pages/man2/rename.2.html).
- Alternative: remount/rebuild/restart; rejected by the no-migration/no-lifecycle constraint.

## Save concurrency and UI

- Decision: shared operation coordination, whole-file revisions, exact target/endpoint IDs and once-only idempotency. Capture inputs before POST; retain drafts on errors and ignore late results from old targets.
- Rationale: polling/dashboard refresh must not reset inputs or duplicate writes. No network probes, drivers or secret-bearing responses needed.
