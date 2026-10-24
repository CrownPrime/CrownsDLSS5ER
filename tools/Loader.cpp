// CrownsDLSS5ER_Loader.dll: brings the DLSS 5 setup into mod packs whose own launcher writes the me3 profile on every
// launch (ELDEN RING Reforged: every DLL in dll\offline). The manager puts this DLL there, next to
// CrownsDLSS5ER_Loader.txt, which lists the DLLs to load, one full path per line, in order: ReShade64.asi (loads
// EldenRingDLSS.addon64, real DLSS in place of TAA), then OptiScaler.dll (DLSS 5). They stay in the CrownsDLSS5
// install, so they keep the manager's settings. What happened goes to CrownsDLSS5ER_Loader.log next to this DLL.
// Built into the release by tools\Build-Release.ps1.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace {

wchar_t g_dir[MAX_PATH];
HANDLE g_log = INVALID_HANDLE_VALUE;

void Log(const wchar_t* text) {
  if (g_log == INVALID_HANDLE_VALUE) return;
  char utf8[2048];
  int n = WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8, sizeof(utf8) - 2, nullptr, nullptr);
  if (n <= 0) return;
  utf8[n - 1] = '\r';
  utf8[n] = '\n';
  DWORD written = 0;
  WriteFile(g_log, utf8, n + 1, &written, nullptr);
}

void LoadListed() {
  wchar_t path[MAX_PATH];
  lstrcpyW(path, g_dir);
  lstrcatW(path, L"CrownsDLSS5ER_Loader.log");
  g_log = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);

  lstrcpyW(path, g_dir);
  lstrcatW(path, L"CrownsDLSS5ER_Loader.txt");
  HANDLE list = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (list == INVALID_HANDLE_VALUE) {
    Log(L"CrownsDLSS5ER_Loader.txt not found: nothing loaded. Press PLAY in the CrownsDLSS5ER manager.");
    return;
  }
  char data[8192];
  DWORD size = 0;
  ReadFile(list, data, sizeof(data) - 1, &size, nullptr);
  CloseHandle(list);
  data[size] = 0;

  // One UTF-8 path per line; a BOM, blank lines and lines starting with # are skipped.
  char* line = data;
  if (size >= 3 && (unsigned char)data[0] == 0xEF && (unsigned char)data[1] == 0xBB && (unsigned char)data[2] == 0xBF) line += 3;
  while (*line) {
    char* end = line;
    while (*end && *end != '\r' && *end != '\n') ++end;
    const char next = *end;
    *end = 0;
    if (*line && *line != '#') {
      wchar_t dll[MAX_PATH];
      wchar_t msg[MAX_PATH + 96];
      if (MultiByteToWideChar(CP_UTF8, 0, line, -1, dll, MAX_PATH) > 0) {
        // Under the loader lock, as an ASI loader would: ReShade has to be in before the game creates its D3D12 device.
        if (LoadLibraryW(dll)) {
          lstrcpyW(msg, L"loaded ");
        } else {
          wsprintfW(msg, L"FAILED (error %lu) ", GetLastError());
        }
        lstrcatW(msg, dll);
        Log(msg);
      }
    }
    if (!next) break;
    line = end + 1;
  }
  CloseHandle(g_log);
  g_log = INVALID_HANDLE_VALUE;
}

}  // namespace

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(module);
    DWORD n = GetModuleFileNameW(module, g_dir, MAX_PATH);
    while (n > 0 && g_dir[n - 1] != L'\\') --n;
    g_dir[n] = 0;
    LoadListed();
  }
  return TRUE;  // never fail the host: without the DLSS 5 setup the mod still starts
}
