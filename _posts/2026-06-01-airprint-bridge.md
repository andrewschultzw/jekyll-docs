---
layout: post
title: "Killing the 30-Copy Loop: A CUPS + Avahi AirPrint Bridge"
date: 2026-06-01
---

The Brother HL-2270DW in the office had a habit that ranged from annoying to
paper-tray-emptying: every so often a single print job would come out 30+ times.
This is the story of tracking that down to its real cause and replacing the
culprit with a small, fully-controllable Linux container. Full reference doc:
[AirPrint Bridge (CUPS + Avahi)](/docs/services/airprint-bridge/).

## It was never a copy count

The HL-2270DW has no native AirPrint, so something has to bridge mDNS/IPP to the
printer. The Synology DSM print server was doing that job. DSM sends jobs to the
Brother over LPD, and when the printer's embedded LPD daemon fails to return a
clean job-complete ack, CUPS re-spools the **entire job** and tries again. The
"30 copies" was never a setting — it was the *same job* printed on a loop until
something cancelled it.

The frustrating part: DSM is a black box. There's no exposed knob for the error
policy or retry limit. So the only real fix is to move the bridge somewhere with
a real knob.

## The fix is one line

Stand up a dedicated CUPS + Avahi LXC and add the printer queue with:

```
printer-error-policy=abort-job
```

That tells CUPS: if a job fails at the backend, fail it **once** and stop — do not
re-spool it. Everything else in the build is just plumbing around that one option.

## The build, briefly

A Debian 12 unprivileged container on Proxmox (CT 117, `192.168.1.149`), then:

```bash
apt install -y cups cups-filters avahi-daemon avahi-utils printer-driver-brlaser
lpadmin -p BrotherHL2270DW -E \
  -v "lpd://192.168.1.150/BINARY_P1" \
  -m "drv:///brlaser.drv/br2270dw.ppd" \
  -o printer-error-policy=abort-job \
  -o printer-is-shared=true
cupsctl --share-printers
```

Modern CUPS advertises shared queues to AirPrint over DNS-SD automatically as long
as Avahi is up — no hand-written service file. The phones pick it up as
"BrotherHL2270DW @ airprint" with no app required.

## Two things the runbook didn't see coming

The plan was clean, but the live box surfaced two surprises.

**`cups-browsed` was quietly recreating the bug.** Debian ships `cups-browsed`
enabled, and it auto-imports printers it discovers on the network. On a fresh
install it found the *Synology's* still-live AirPrint advertisement and created a
local mirror queue — with `ErrorPolicy retry-job`. That's the exact respool
behavior I was there to eliminate, re-introduced automatically. A print bridge
should export one queue and import none, so `cups-browsed` got disabled.

**`colord` was stalling startup.** CUPS in a headless container kept timing out
trying to reach the `colord` color-management daemon over DBus — 25 seconds a pop,
delaying cupsd coming up. Color management means nothing to a monochrome laser, so
masking `colord` made the calls fail instantly. Clean logs, fast restarts.

## A note on verification

The right division of labor on a job like this: I can verify the config, the
driver, the DNS-SD advertisement, and the logs all day — but only a human at the
printer can confirm that exactly one page comes out. So that was the acceptance
gate. A print from an iPhone produced a single copy, and a container-side test job
completed and cleared just as cleanly. The 30-copy loop is structurally gone, and
the old Synology print server has been decommissioned.

Total footprint: a 512 MB container that does exactly one thing and can't get it
wrong.
