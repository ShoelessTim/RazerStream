---
name: Device report (help add support for your deck)
about: Report a Loupedeck or Razer device that RazerStream does not support yet
title: "[device] "
labels: device-report
---

Thanks for helping. Adding a device needs two things: what it identifies
itself as over USB, and how it behaves. The first is a one line command.

## 1. Get the report

In RazerStream: **Settings > Device > Copy Device Report**. That puts it on
your clipboard, ready to paste below. You do not need Terminal.

(Building from source? `swift run rstream report` prints the same thing.)

It prints hardware facts only: USB ids, product strings, and the firmware
line if your device already speaks the protocol. It does not read your
profiles, your files, or anything personal, so it is safe to paste publicly.
Read it first if you would rather check.

**Paste the output here:**

```
(paste the block here)
```

## 2. Tell us about the device

- **Which model is it?** (Loupedeck Live, Loupedeck CT, Loupedeck+, Razer
  Stream Controller X, something else)
- **Does the official Loupedeck or Logitech software still drive it on this
  Mac?**
- **What does it physically have?** Number of touchscreen keys, dials, and
  buttons, and whether it has a wheel.

## 3. Optional, and very useful

If your device appears in the report but RazerStream cannot drive it, the
next thing needed is a capture of the official software talking to it. Say
so in this issue and we will walk through it; no need to figure that out on
your own.

If you also used the Loupedeck software and want its profiles supported,
mention that too. Please do not paste profile files directly, they can
contain your shortcuts and URLs; we will sort out a safe way to share them.
