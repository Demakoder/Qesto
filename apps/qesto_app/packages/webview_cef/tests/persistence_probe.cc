// Explicit native regression probe. No bank/network login and no user profile.
// Run twice with the same NEW fixture root: --probe-mode=write, then read.
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include "include/cef_app.h"
#include "include/cef_command_line.h"
#include "include/cef_sandbox_win.h"
#include "include/base/cef_callback.h"
#include "include/wrapper/cef_closure_task.h"
#include "webview_handler.h"
#include "persistent_profile_path.h"

namespace {
std::string root, mode;
CefRefPtr<WebviewHandler> handler;
int active = -1;
int outcome = 1;
bool finished = false;
const char* origin = "https://qesto-fixture.invalid/";
void Stage(const char* value) {
  std::ofstream(QestoUtf8Path(root) / "stages.log", std::ios::app) << value << '\n';
}
class ProbeHandler : public WebviewHandler {
 public:
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    Stage("native-browser-created");
    Stage(browser->GetHost()->GetRequestContext()->GetCachePath().empty()
      ? "context-cache-empty" : "context-cache-present");
    WebviewHandler::OnAfterCreated(browser);
  }
};

void Finish(bool ok) {
  if (finished) return;
  finished = true;
  outcome = ok ? 0 : 1;
  std::ofstream(QestoUtf8Path(root) / ("probe-" + mode + ".result")) << (ok ? "PASS" : "FAIL");
  if (active >= 0) {
    handler->closeBrowser(active, [] { active = -1; CefQuitMessageLoop(); });
  } else {
    CefQuitMessageLoop();
  }
}

class SetDone : public CefSetCookieCallback {
 public:
  explicit SetDone(std::function<void(bool)> fn) : fn_(std::move(fn)) {}
  void OnComplete(bool ok) override { fn_(ok); }
 private:
  std::function<void(bool)> fn_;
  IMPLEMENT_REFCOUNTING(SetDone);
};

class Visitor : public CefCookieVisitor {
 public:
  explicit Visitor(std::function<void(bool)> done, bool expect_present = true)
      : done_(std::move(done)), expect_present_(expect_present) {}
  ~Visitor() override {
    done_(expect_present_ ? session_ && persistent_ : !session_ && !persistent_);
  }
  bool Visit(const CefCookie& cookie, int, int, bool& remove) override {
    remove = false;
    const auto name = CefString(&cookie.name).ToString();
    const auto value = CefString(&cookie.value).ToString();
    if (name == "qesto_fixture_session" && value == "synthetic" && !cookie.has_expires) session_ = true;
    if (name == "qesto_fixture_persistent" && value == "synthetic" && cookie.has_expires) persistent_ = true;
    return true;
  }
 private:
  bool session_ = false, persistent_ = false;
  std::function<void(bool)> done_;
  bool expect_present_;
  IMPLEMENT_REFCOUNTING(Visitor);
};

void ReadCookies() {
  Stage("read-cookies");
  const auto browser = CefBrowserHost::GetBrowserByIdentifier(active);
  const auto manager = browser->GetHost()->GetRequestContext()->GetCookieManager(nullptr);
  manager->VisitUrlCookies(origin, true,
      new Visitor([](bool ok) { Finish(ok); }, mode != "read-isolated"));
}

void Open(bool write) {
  Stage("open-start");
  // This is the actual production creator, path validation and native close.
  const auto profile = QestoNativeProfilePath(root +
      (mode == "read-isolated" ? "/isolated-profile" : "/fixture-profile"));
  handler->createBrowser("about:blank", profile, {"https://qesto-fixture.invalid"}, false,
    [write](int id) {
      Stage("create-callback");
      if (id < 0) { Finish(false); return; }
      active = id;
      if (!write) { ReadCookies(); return; }
      const auto manager = CefBrowserHost::GetBrowserByIdentifier(id)->GetHost()->GetRequestContext()->GetCookieManager(nullptr);
      CefCookie cookie;
      CefString(&cookie.name) = "qesto_fixture_session";
      CefString(&cookie.value) = "synthetic";
      CefString(&cookie.path) = "/";
      cookie.secure = true;
      cookie.httponly = true;
      manager->SetCookie(origin, cookie, new SetDone([manager](bool ok) {
        Stage("session-cookie-callback");
        if (!ok) { Finish(false); return; }
        CefCookie persistent;
        CefString(&persistent.name) = "qesto_fixture_persistent";
        CefString(&persistent.value) = "synthetic";
        CefString(&persistent.path) = "/";
        persistent.secure = true;
        persistent.httponly = true;
        persistent.has_expires = true;
        persistent.expires = CefBaseTime::Now();
        persistent.expires.val += 86400LL * 1000000LL;
        manager->SetCookie(origin, persistent, new SetDone([](bool saved) {
          Stage("persistent-cookie-callback");
          if (!saved) { Finish(false); return; }
          handler->closeBrowser(active, [] {
            active = -1;
            CefPostTask(TID_UI, base::BindOnce([] { Open(false); }));
          });
        }));
      }));
    });
}
}

CEF_BOOTSTRAP_EXPORT int RunWinMain(HINSTANCE instance, LPTSTR, int, void* sandbox,
                                    cef_version_info_t*) {
  CefMainArgs args(instance);
  auto app = CefRefPtr<CefApp>();
  const int subprocess = CefExecuteProcess(args, app, sandbox);
  if (subprocess >= 0) return subprocess;
  auto command = CefCommandLine::CreateCommandLine();
  command->InitFromString(GetCommandLineW());
  root = QestoNativeProfilePath(command->GetSwitchValue("probe-root").ToString());
  mode = command->GetSwitchValue("probe-mode").ToString();
  const auto path = QestoUtf8Path(root);
  if (!path.is_absolute() || path.filename().wstring().find(L"qesto-cef-probe-") != 0 ||
      (mode != "write" && mode != "read" && mode != "read-isolated")) return 2;
  std::filesystem::create_directories(path);
  if (!QestoIsPersistentProfilePath(root, (path / "fixture-profile").string()) ||
      QestoIsPersistentProfilePath(root, (path / "fixture-profile" / "cef").string()) ||
      QestoIsPersistentProfilePath(root, root)) return 3;
  CefSettings settings;
  settings.windowless_rendering_enabled = true;
  settings.no_sandbox = false;
  settings.log_severity = LOGSEVERITY_DISABLE;
  CefString(&settings.root_cache_path) = root;
  if (!CefInitialize(args, settings, app, sandbox)) return 4;
  handler = new ProbeHandler();
  handler->storage_root = root;
  CefPostTask(TID_UI, base::BindOnce([] { Open(mode == "write"); }));
  CefPostDelayedTask(TID_UI, base::BindOnce([] { Finish(false); }), 30000);
  CefRunMessageLoop();
  handler = nullptr;
  CefShutdown();
  return outcome;
}
