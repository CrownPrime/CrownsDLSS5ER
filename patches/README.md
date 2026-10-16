# Source changes

## OptiScaler (GPL-3.0): `crownsdlss5er-optiscaler-f45ccf3a.patch`

The release ships a modified build of the OptiScaler DLSS-NR fork. Under GPL-3.0, its complete source is
available here.

- **Base:** [wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass),
  commit `f45ccf3a761df91450959d325ac0166cba5364c9` (the v0.8.91 build).
- **Changes:** three files, `OptiScaler/menu/menu_common.cpp`, `OptiScaler/dlssnr/DlssNr_PipelineUi.h` and
  `OptiScaler/dlssnr/DlssNr_Menu.cpp`. They add:
  - a CrownsDLSS5ER header with the emblem drawn as ImGui shapes;
  - the window title;
  - theme colour defaults;
  - gold in place of green in the DLSS-NR panel.

**To build it yourself:**

```
git clone https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass.git
cd OptiScaler-DLSSNR-PreSR-Multipass
git checkout f45ccf3a761df91450959d325ac0166cba5364c9
git submodule update --init --depth 1
git apply path\to\crownsdlss5er-optiscaler-f45ccf3a.patch
msbuild OptiScaler.sln /t:OptiScaler /p:Configuration=Release /p:Platform=x64
```

That needs Visual Studio 2022 with the C++ tools (toolset v143).

The same change is committed, ready to clone and build, on the public fork:
**[CrownPrime/OptiScaler-DLSSNR-PreSR-Multipass @ `crownsdlss5er`](https://github.com/CrownPrime/OptiScaler-DLSSNR-PreSR-Multipass/tree/crownsdlss5er)** (commit `63014c2`).

## EldenRingDLSS (MIT): `EldenRingDLSS-0.1.0-crownsdlss5er.patch`

- **Base:** [masonpetrosky/EldenRingDLSS](https://github.com/masonpetrosky/EldenRingDLSS) v0.1.0. Apply the patch to
  its `src/` folder and build with its `build.ps1`.
- **Changes:**
  - **Device rebinding:** if the D3D12 device DLSS was set up on is destroyed (for example a short-lived
    integrated-GPU device), the add-on moves to the remaining device.
  - **ReShade proxy objects for NGX:** NGX gets ReShade's proxy command list, and is re-initialised on that list's
    device. This fixes a crash in `D3D12Core!SetDescriptorHeapsInternal` when the DLSS-NR model records into the
    unwrapped list.
