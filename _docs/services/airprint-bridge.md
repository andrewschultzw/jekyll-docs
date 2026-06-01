---
layout: default
title: AirPrint Bridge (CUPS + Avahi)
parent: Services
grand_parent: Docs
nav_order: 3
---

# AirPrint Bridge — Brother HL-2270DW

**Container:** CT 117 (`192.168.1.149`)
**Host:** Proxmox VE 9.1.1 (`192.168.1.10`)
**Stack:** Debian 12 LXC (unprivileged) · CUPS · Avahi · `brlaser`
**Printer:** Brother HL-2270DW (`192.168.1.150`), LPD queue `BINARY_P1`
**Queue name:** `BrotherHL2270DW`

## Overview

A dedicated CUPS + Avahi container that advertises the Brother HL-2270DW to
iPhones and Android phones over AirPrint. The HL-2270DW has no native AirPrint,
so something has to bridge mDNS/IPP to the printer. This LXC does that job — and,
critically, it caps the resend behavior at the source so the printer can never be
driven into a runaway copy loop.

## The problem this solves

The Synology DSM print server used to be the bridge. DSM is a black box: it sends
jobs to the Brother over LPD, and when the printer's embedded LPD daemon fails to
return a clean job-complete ack, CUPS re-spools the **whole job** and tries again.
That retry loop is the infamous "30+ copies" — it was never a copy-count setting,
it was the *same job* printed over and over until someone cancelled it. DSM gives
no way to change the error policy, so the fix is to move the bridge somewhere with
a real knob.

That knob is one CUPS option:

```
printer-error-policy=abort-job
```

It tells CUPS: if a job fails at the backend, **fail it once, do not re-spool it.**
That single option is what kills the loop.

## Architecture

```
iPhone / Android ──mDNS (UDP 5353)──▶ CT 117 airprint  (Avahi advertises AirPrint)
                  ──IPP  (TCP 631)──▶ CT 117 airprint  (CUPS accepts the job)
                                            │
                                            │ brlaser renders → PCL/raster
                                            ▼
                                      LPD (TCP 515) ──▶ Brother HL-2270DW (.150)
                                            BINARY_P1 queue · error-policy=abort-job
```

The network is a flat `/24` (Proxmox `vmbr0`, no VLANs), so the phones, the
container, and the printer all share one L2 — no cross-VLAN mDNS work needed.

## Known-good printer values

| Field        | Value                                       |
| ------------ | ------------------------------------------- |
| Printer IP   | `192.168.1.150`                             |
| Protocol     | LPD                                         |
| Queue name   | `BINARY_P1`                                 |
| Driver       | `brlaser` → `drv:///brlaser.drv/br2270dw.ppd` |
| Command set  | PJL, PCL, PCLXL                             |

## Build

### 1. Create the LXC (on the Proxmox host)

```bash
pct create 117 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname airprint \
  --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.149/24,gw=192.168.1.1 \
  --unprivileged 1 --onboot 1 --features nesting=1 \
  --description "AirPrint bridge for Brother HL-2270DW (CUPS+Avahi)"
pct start 117
```

> **Pick a free IP — don't assume `.<CTID>` is open.** `.117` was already a Sonos,
> and `.117–.122` is the DHCP pool. `.149` is a static slot in the static-server
> zone, right beside the printer at `.150`. A UniFi DHCP reservation locks it to
> the container's MAC.

### 2. Inject the management SSH key

`ssh-copy-id` fails on a fresh container (no root password), so push the admin
key from the Proxmox host:

```bash
pct exec 117 -- bash -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && \
  echo "<admin-pubkey>" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'
```

### 3. Install CUPS, Avahi, and the driver

```bash
apt update && apt -y upgrade
apt install -y cups cups-filters avahi-daemon avahi-utils printer-driver-brlaser
systemctl enable --now cups avahi-daemon
```

### 4. Add the printer with the loop killed at the source

```bash
# Confirm the exact PPD brlaser registered:
lpinfo -m | grep -i 2270
# → drv:///brlaser.drv/br2270dw.ppd  Brother HL-2270DW series, using brlaser v6

lpadmin -p BrotherHL2270DW -E \
  -v "lpd://192.168.1.150/BINARY_P1" \
  -m "drv:///brlaser.drv/br2270dw.ppd" \
  -L "Office" \
  -o printer-error-policy=abort-job \
  -o printer-is-shared=true

cupsenable BrotherHL2270DW
cupsaccept BrotherHL2270DW
```

Confirm the policy actually persisted:

```bash
grep -A1 BrotherHL2270DW /etc/cups/printers.conf | grep ErrorPolicy
# → ErrorPolicy abort-job
```

### 5. Share and advertise over AirPrint

Modern CUPS advertises shared queues to AirPrint automatically via DNS-SD as long
as Avahi is running — no hand-written `.service` file required.

```bash
cupsctl --share-printers
systemctl restart cups avahi-daemon

avahi-browse -rt _ipp._tcp
```

The advertisement is AirPrint-ready when its TXT record carries
`pdl=...,image/urf` and a `_universal._sub._ipp._tcp` entry appears. That `urf`
raster type is exactly what makes iOS treat it as a real AirPrint printer.

## Two gotchas worth knowing

These weren't in the original runbook — they were found during the build.

### `cups-browsed` auto-imports other printers (disable it)

On Debian 12, `cups-browsed` ships **enabled**. On a fresh box it discovered the
Synology's still-live AirPrint advertisement and silently created a local mirror
queue — *with `ErrorPolicy retry-job`, the exact respool behavior being eliminated.*
A bridge should **export one queue and import none**:

```bash
systemctl disable --now cups-browsed
lpadmin -x <auto-created-mirror-queue> 2>/dev/null
```

If a stale `<Printer …>` stanza lingers in `/etc/cups/printers.conf`, stop cupsd,
delete the block, then start cupsd — never edit that file while cupsd is running
(it overwrites on stop).

### `colord` DBus timeouts (mask it)

CUPS in a headless LXC logs repeated `CreateProfile`/`CreateDevice … ColorManager`
DBus errors — 25-second timeouts each that delay cupsd startup — because `colord`
has no usable session. Color management is irrelevant for a mono laser:

```bash
systemctl mask colord
systemctl restart cups
```

The remaining "Printer drivers are deprecated" and "UnitMasked" log lines are
benign.

## Verification

```bash
# Submit one job and watch it:
lp -d BrotherHL2270DW /etc/hostname
watch -n1 lpstat -o          # job appears, then clears
tail -f /var/log/cups/error_log
```

**Pass criteria:** one job ID appears, prints **once**, and clears. There should be
no repeating job ID and no "will retry" messages. Validated end-to-end on
2026-06-01 — a phone print and a container-side print both completed cleanly, one
copy each, no respool.

## Day-to-day management

| Task                          | Command                                            |
| ----------------------------- | -------------------------------------------------- |
| Queue / job status            | `lpstat -t`                                         |
| List pending jobs             | `lpstat -o`                                         |
| Cancel a stuck job            | `cancel BrotherHL2270DW-<n>`                        |
| Re-enable after a fault       | `cupsenable BrotherHL2270DW`                        |
| Live AirPrint advertisement   | `avahi-browse -rt _ipp._tcp`                        |
| CUPS web UI (from LAN)        | `https://192.168.1.149:631` (run `cupsctl --remote-admin` first) |

## Troubleshooting

### Phone can't find the printer

Almost always mDNS reachability. Confirm `avahi-daemon` is running, the container
is bridged onto the phones' L2, and `avahi-browse -rt _ipp._tcp` shows
`BrotherHL2270DW @ airprint`. On a segmented network you'd also need mDNS
reflection across VLANs — not applicable on this flat `/24`.

### Garbled output (not copies)

Wrong driver/PPD. Re-run `lpinfo -m | grep -i 2270` and confirm the queue uses the
`brlaser` `br2270dw.ppd` model string, not a generic raw queue.

### The loop somehow comes back on LPD

Switch the backend to a raw socket wrapped in the backend error handler (`beh`),
which hard-caps retries regardless of acks:

```bash
lpadmin -p BrotherHL2270DW -v "beh:/1/2/30/socket://192.168.1.150:9100"
# beh fields: /<don't-disable-queue>/<max attempts>/<delay seconds>/<real URI>
```

### Need more log detail

```bash
cupsctl --debug-logging       # reproduce the issue
cupsctl --no-debug-logging    # revert when done
```

## Rollback

The Synology print server is the fallback. Re-add it in DSM with the known-good
values: **Control Panel → External Devices → Printer → Add Network Printer →**
IP `192.168.1.150`, LPD, queue `BINARY_P1`.
