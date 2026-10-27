# Neural vPool / uVRAM Engine &mdash; v11

**Frame pacing for phones.** A non-root Termux engine that targets frame-time consistency across 60 / 90 / 120 / 144 Hz panels, backed by a virtual memory pool that absorbs the spikes most tuning scripts ignore.

Android only, no root, no server. Free Fire and Free Fire Max are the tuned targets.

## What it actually does

| Component | Purpose |
| --- | --- |
| **Frame pacing (AFB)** | Smooths the interval between frames &mdash; that interval, not the average FPS number, is what you feel as stutter |
| **vPool** | A managed virtual memory pool, sized from the device, for scene-transition spikes |
| **uVRAM** | Memory headroom management without root |
| **ARC+** | Cache warm-up and scheduler hints |
| **Thermal guard** | Steps the profile down before the SoC throttles itself |
| **Auto-start** | Re-applies the profile when the device boots |
| **Live FPS readout** | On-screen counter so you can see the effect instead of guessing |

## Run

```bash
pkg install -y git
git clone https://github.com/hypersenseindia/neural-vpool-uvram-engine-v11
cd neural-vpool-uvram-engine-v11
chmod +x *.sh
ls                # confirm the entry script name
./engine.sh
```

> If the entry script has a different name in this build, run the `.sh` file listed by `ls`.

## Versions

- **v11** &mdash; this repository, current
- [v10](https://github.com/hypersenseindia/neural-vpool-uvram-engine-v10) &mdash; previous build, kept for reference

## Honest expectations

A script cannot exceed what the firmware and the SoC allow. Tuning can realistically:

- reduce frame-time variance (smoother, not faster)
- avoid unnecessary background load
- keep the device out of thermal throttling for longer

It cannot add GPU performance the hardware does not have, or change the game's own rendering settings.

---

<p align="center">
  <sub>Built by <b>AG HYDRAXFF</b> &mdash; HYPERSENSEGLOBAL &middot;
  <a href="https://www.instagram.com/hydraxff_yt/">@hydraxff_yt</a></sub>
</p>