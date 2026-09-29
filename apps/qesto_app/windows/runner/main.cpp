#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "include/cef_sandbox_win.h"
#include "webview_cef/webview_cef_plugin_c_api.h"

#include "flutter_window.h"
#include "utils.h"

// Called by the official CEF bootstrap executable. Keeping the Flutter runner
// in a client DLL is the supported Windows sandbox model for CEF M138+.
CEF_BOOTSTRAP_EXPORT int RunWinMain(HINSTANCE instance,
                                    LPTSTR command_line,
                                    int show_command,
                                    void* sandbox_info,
                                    cef_version_info_t* version_info) {
  // Qesto's encrypted local store is intentionally single-writer. Prevent two
  // desktop instances from racing on the same atomic snapshot. This check has
  // to happen before CEF initializes in a second browser process; otherwise
  // that short-lived process can contend with the active Chromium runtime.
  // CEF renderer/GPU subprocesses carry --type= and must bypass the mutex.
  const bool is_cef_subprocess =
      ::wcsstr(::GetCommandLineW(), L"--type=") != nullptr;
  HANDLE single_instance = nullptr;
  if (!is_cef_subprocess) {
    single_instance =
        ::CreateMutexW(nullptr, TRUE, L"Local\\Qesto.Desktop.SingleInstance");
    if (single_instance != nullptr &&
        ::GetLastError() == ERROR_ALREADY_EXISTS) {
      if (HWND existing_window = ::FindWindowW(nullptr, L"Qesto")) {
        ::ShowWindow(existing_window, SW_RESTORE);
        ::SetForegroundWindow(existing_window);
      }
      ::CloseHandle(single_instance);
      return EXIT_SUCCESS;
    }
  }

  const int cef_exit_code = initCEFProcesses(instance, sandbox_info);
  if (cef_exit_code >= 0) {
    if (single_instance != nullptr) {
      ::ReleaseMutex(single_instance);
      ::CloseHandle(single_instance);
    }
    return cef_exit_code;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Qesto", origin, size)) {
    if (single_instance != nullptr) {
      ::CloseHandle(single_instance);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    handleWndProcForCEF(msg.hwnd, msg.message, msg.wParam, msg.lParam);
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr) {
    ::ReleaseMutex(single_instance);
    ::CloseHandle(single_instance);
  }
  return EXIT_SUCCESS;
}
