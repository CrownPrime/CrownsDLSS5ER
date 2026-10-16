# Third-party notices

The CrownsDLSS5ER release zip bundles these components. Each one keeps its own licence, and the licence texts
are in `licenses/`.

| Component | Version | Licence | Notes |
| --- | --- | --- | --- |
| [OptiScaler DLSS-NR fork](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass) (`OptiScaler.dll`, `OptiScaler/`) | v0.8.91 (commit `f45ccf3a`), **modified** | GPL-3.0 (`licenses/OptiScaler/LICENSE`) | CrownsDLSS5ER changes: an in-menu header with the emblem drawn as vector shapes, the window title, and the menu theme. Full source of the modified version: [CrownPrime/OptiScaler-DLSSNR-PreSR-Multipass, branch `crownsdlss5er`](https://github.com/CrownPrime/OptiScaler-DLSSNR-PreSR-Multipass/tree/crownsdlss5er), also as `patches/`. |
| AMD FidelityFX SDK (inside `OptiScaler/`) | as shipped by the fork | MIT (`licenses/OptiScaler/FidelityFX_*`) | |
| Intel XeSS (inside `OptiScaler/`) | as shipped by the fork | Intel Simplified Software License (`licenses/OptiScaler/XeSS_LICENSE.txt`) | Redistributed unmodified. |
| Microsoft DirectX Agility SDK `D3D12Core.dll` (inside `OptiScaler/`) | as shipped by the fork | Microsoft DirectX licence (`licenses/OptiScaler/DirectX_LICENSE.txt`) | Distributable code. |
| [EldenRingDLSS](https://github.com/masonpetrosky/EldenRingDLSS) ReShade add-on (`EldenRingDLSS.addon64`) | 0.1.0, **modified** | MIT (`licenses/EldenRingDLSS/LICENSE.txt`) | Copyright Mason Petrosky. CrownsDLSS5ER changes: rebinding to the surviving D3D12 device, and passing ReShade's proxy command list to NGX. Diff: `patches/EldenRingDLSS-0.1.0-crownsdlss5er.patch`. |
| [ReShade](https://reshade.me) (`ReShade64.asi`) | 6.8.0, add-on build | BSD-3-Clause (`licenses/EldenRingDLSS/ReShade-LICENSE.md`) | Copyright Patrick Mours. Unmodified. |
| Dear ImGui (headers used by the add-on) | | MIT (`licenses/EldenRingDLSS/ImGui-LICENSE.txt`) | |
| NVIDIA DLSS runtime (`nvngx_dlss.dll`, `nvngx_dlssd.dll`) and the DLSS SDK linked into the add-on | 310.9.x | NVIDIA RTX SDKs licence (`licenses/EldenRingDLSS/NVIDIA-RTX-SDKs-LICENSE.txt`) | Redistributed unmodified as part of this application. |
| [me3](https://github.com/garyttierney/me3) mod loader (`pack/me3/`) | 0.13.0 | MIT (`licenses/me3/LICENSE-MIT`) | Unmodified. |

## Not included

- **`nvngx_dlssnr.dll`, the NVIDIA DLSS 5 / neural rendering model.** It's NVIDIA's file and isn't
  redistributable. Users supply their own copy (see README).

## Attribution

This software uses **NVIDIA DLSS**. NVIDIA, the NVIDIA logo and DLSS are trademarks and/or registered trademarks of
NVIDIA Corporation in the U.S. and other countries.

ELDEN RING is a trademark of FromSoftware, Inc. / Bandai Namco Entertainment Inc. CrownsDLSS5ER is a fan-made tool.
It is not affiliated with or endorsed by FromSoftware, Bandai Namco, NVIDIA, AMD, Intel, Microsoft, or the
authors of OptiScaler, EldenRingDLSS, ReShade or me3.
