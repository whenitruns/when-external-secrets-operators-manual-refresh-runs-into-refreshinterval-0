# When External Secrets Operator's Manual Refresh Runs Into `refreshInterval: 0` — reproduction

When It Runs — Run Report #RR11 · Testing what infrastructure actually does.

Run Report: https://whenitruns.substack.com/p/when-external-secrets-operators-manual

This repository holds the reproduction from the report above: the manifest printed in its §4 (Reproduction), byte for byte, and the commands its §4 prints, run one step at a time. Nothing here adds versions, configurations, or findings beyond the report.

## Setup pinned in the report

- External Secrets Operator v2.11.0, installed from the official Helm chart `external-secrets-2.11.0.tgz` (release asset of `helm-chart-2.11.0`; sha256 `8199b42fe80b871c6a86233a80bb14f599fd6e1e6462c1216d836577f845e161`), image `ghcr.io/external-secrets/external-secrets:v2.11.0` (`sha256:66fb710878cbf3eba4a927e35c5d75e29a202c9bab238aad64bfb23b786b962b`). The only chart value set is `log.level=debug`, so that the controller's `skipping refresh` line is visible.
- A single-node `kind` cluster (kind v0.33.0), node image `kindest/node:v1.36.4` (digest-pinned); `kubectl` v1.36.5.
- One `SecretStore` using the `fake` provider and three `ExternalSecret`s that differ only in their refresh settings (`rr11.yaml`); none sets a creation policy, so all use the default, `Owner`.
- Verified on: 2026-10-17 (desk sources re-checked; v2.13.0 was the current minor release) · lab measured 2026-09-28 on v2.11.0 — re-verification against the then-current release happens at publication.

## Not scripted here

The report describes these without printing a command for them, so they are not scripted:

- the 120-second polling after each change — `./reproduce.sh poll` runs the three poll commands once; the report runs them every 5 seconds for 120 seconds after the store change and after each of the five changes;
- reading the results side by side — for each window, whether the target Secret's keys, values and `resourceVersion`, and the `ExternalSecret`'s `refreshTime` and `syncedResourceVersion`, changed.

## Files

| File | From the report |
|---|---|
| `rr11.yaml` | §4 — the namespace, the `fake` store and the three `ExternalSecret`s, byte for byte |
| `reproduce.sh` | §4 — every line of its block, with the commands it prints, one step per run |

## Run order

On a test machine with `kind`, `helm` and `kubectl` as pinned above (all times UTC):

1. `./reproduce.sh 0` — create the `kind` cluster `rr11`, install External Secrets Operator v2.11.0 with the controller at log level `debug`, and list the pods.
2. `./reproduce.sh 1` — apply `rr11.yaml` and wait until all three `ExternalSecret`s are `Ready`; then `./reproduce.sh poll` for the T0 state.
3. `./reproduce.sh 2` — change the store value to `value-2`; then `./reproduce.sh poll` every 5 seconds for 120 seconds.
4. `./reproduce.sh 3-annotation`, `./reproduce.sh 3-label`, `./reproduce.sh 3-spec` — the FAQ's three changes on `es-zero`, one at a time, each followed by 120 seconds of polling.
5. `./reproduce.sh 4-hourly`, then `./reproduce.sh 4-onchange` — the same annotation change on the two comparison `ExternalSecret`s, each followed by 120 seconds of polling.
6. `./reproduce.sh 5` — delete the test cluster `rr11`.

## Expected observation

From the report (§3):

> **Store value changed to `value-2`** (00:04:40): in the 120 seconds that followed, none of the three Secrets changed — each held `token=value-1` with the same `resourceVersion` at every poll — and no object's `refreshTime` or `syncedResourceVersion` changed. The store change alone refreshed nothing.

> **`es-zero`, annotation (the FAQ's command)** (00:06:40): for all 120 seconds, the Secret held `token=value-1` with `resourceVersion` 755; the object's `refreshTime` stayed 00:04:39, its `syncedResourceVersion` kept its T0 value, and its `Ready` condition stayed `True` (`SecretSynced`, last transition 00:04:39). The controller logged one `skipping refresh` line for `es-zero`, at 00:06:40, as the change landed.

> **`es-zero`, label** (`rr11/probe=1`, 00:08:41): the same — `token=value-1`, `resourceVersion` 755, `refreshTime` 00:04:39, and `syncedResourceVersion` and `Ready` unchanged for 120 seconds; one `skipping refresh` line for `es-zero`, at 00:08:41.

> **`es-zero`, spec change — a new data key (`token2`, mapped to the same store key; `metadata.generation` goes up by one):** (00:10:41; `metadata.generation` went from 1 to 2) `token2` never appeared in the Secret: for 120 seconds it held only `token=value-1`, with `resourceVersion` 755; `refreshTime`, `syncedResourceVersion` and `Ready` were unchanged; one `skipping refresh` line for `es-zero`, at 00:10:41.

> **`es-hourly` and `es-onchange`, annotation:** each Secret held `token=value-2` at the first poll, taken as the `annotate` command returned. `es-hourly` (annotated 00:12:42): Secret `resourceVersion` 760 → 1448, `refreshTime` 00:04:39 → 00:12:42. `es-onchange` (annotated 00:14:43): Secret `resourceVersion` 764 → 1623, `refreshTime` 00:04:39 → 00:14:43. For each, the controller logged `reconciled secret`. Through both windows, `es-zero`'s Secret still held `token=value-1`.

> "Did not change" in this section means: at every 5-second poll in the 120-second window, the target Secret's keys, decoded values and `resourceVersion`, and the `ExternalSecret`'s `refreshTime` and `syncedResourceVersion`, were the same as at the start of the window.

The report's own limits (§6):

> **Other creation policies.** We measured only the default, `Owner`. By the source, `isSecretValid` treats a Secret as always valid with `creationPolicy: Orphan` (L1305–1307), and `Merge` and `CreateOrMerge` handle the target differently; we did not measure them.

> **Other providers.** We used the `fake` provider only; we did not test a cloud secret store.

> **Other versions.** Only v2.11.0 was measured; v2.12.0, v2.13.0 and v2.14.0, released on 2026-10-06, 2026-10-16 and 2026-10-23, were not measured; the project supports only the current minor version, and its support table (`docs/introduction/stability-support.md` at v2.13.0) lists 2.11's end of life as 2026-10-06. The v0.11.0 boundary comes from pull request #4086 and its milestone, not from a measurement.

> **Timing.** Each window is 120 seconds after a change. With `refreshInterval: 0`, the API reference says the Secret is created once and not updated afterward (L107), so we did not wait longer.

---

The team behind When It Runs maintains its own test environments and re-verifies findings when new releases change things; that is what the "Verified on" date means.

Licensed under the Apache License 2.0 — see `LICENSE`.
