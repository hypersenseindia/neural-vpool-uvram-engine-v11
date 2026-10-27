# Neural vPool / uVRAM Engine &mdash; v11

**Frame pacing for phones.** A non-root Termux engine that targets frame-time consistency across 60 / 90 / 120 / 144 Hz panels, backed by a virtual memory pool that absorbs the spikes most tuning scripts ignore.

Android only, no root, no server.

## What it actually does

| Component | Purpose |
| --- | --- |
| **Frame pacing** | Smooths the interval between frames, which is what you feel as stutter &mdash; not the average FPS number |
| **vPool** | A managed virtual memory pool, sized from the device, for scene-transition spikes |
| **uVRAM** | Memory headroom management without root |
| **ARC+** | Cache warm-up and scheduler hints |
| **Thermal guard** | Steps the profile down before the SoC does it for you |

## Run

```bash
pkg install -y git
git clone https://github.com/hypersenseindia/neural-vpool-uvram-engine-v11
cd neural-vpool-uvram-engine-v11
chmod +x *.sh
./engine.sh
```

> If the entry script has a different name in this build, list the directory (`ls`) and run the `.sh` file you find there.

## Versions

- **v11** &mdash; this repository, current
- [v10](https://github.com/hypersenseindia/neural-vpool-uvram-engine-v10) &mdash; previous build, kept for reference

## Honest expectations

A script cannot exceed what the firmware and the SoC allow. What tuning can realistically do:

- reduce frame-time variance (smoother, not faster)
- avoid unnecessary background load
- keep the device out of thermal throttling for longer

What it cannot do: add GPU performance the hardware does not have, or change the game's own rendering settings.
---

<p align="center">
  <sub>Built by <b>AG HYDRAXFF</b> &mdash; HYPERSENSEGLOBAL &middot;
  <a href="https://www.instagram.com/hydraxff_yt/">@hydraxff_yt</a></sub>
</p>