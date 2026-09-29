// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_app.h"

#include <string>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_v8.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"

namespace {

// When using the Views framework this object provides the delegate
// implementation for the CefWindow that hosts the Views-based browser.
class SimpleWindowDelegate : public CefWindowDelegate {
public:
    explicit SimpleWindowDelegate(CefRefPtr<CefBrowserView> browser_view)
    : browser_view_(browser_view) {}
    
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        // Add the browser view and show the window.
        window->AddChildView(browser_view_);
        window->Show();
        
        // Give keyboard focus to the browser view.
        browser_view_->RequestFocus();
    }
    
    void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
        browser_view_ = nullptr;
    }
    
    bool CanClose(CefRefPtr<CefWindow> window) override {
        // Allow the window to close if the browser says it's OK.
        CefRefPtr<CefBrowser> browser = browser_view_->GetBrowser();
        if (browser)
            return browser->GetHost()->TryCloseBrowser();
        return true;
    }
    
    CefSize GetPreferredSize(CefRefPtr<CefView> view) override {
        return CefSize(1280, 720);
    }
    
private:
    CefRefPtr<CefBrowserView> browser_view_;
    
    IMPLEMENT_REFCOUNTING(SimpleWindowDelegate);
    DISALLOW_COPY_AND_ASSIGN(SimpleWindowDelegate);
};

class SimpleBrowserViewDelegate : public CefBrowserViewDelegate {
public:
    SimpleBrowserViewDelegate() {}
    
    bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> browser_view,
                                   CefRefPtr<CefBrowserView> popup_browser_view,
                                   bool is_devtools) override {
        // Create a new top-level Window for the popup. It will show itself after
        // creation.
        CefWindow::CreateTopLevelWindow(
                                        new SimpleWindowDelegate(popup_browser_view));
        
        // We created the Window.
        return true;
    }
    
private:
    IMPLEMENT_REFCOUNTING(SimpleBrowserViewDelegate);
    DISALLOW_COPY_AND_ASSIGN(SimpleBrowserViewDelegate);
};

}  // namespace

WebviewApp::WebviewApp(CefRefPtr<WebviewHandler> handler) {
    m_handler = handler;
}

WebviewApp::ProcessType WebviewApp::GetProcessType(CefRefPtr<CefCommandLine> command_line)
{
    // The command-line flag won't be specified for the browser process.
	if (!command_line->HasSwitch("type"))
    {
        return BrowserProcess;
    }

	const std::string& process_type = command_line->GetSwitchValue("type");
	if (process_type == "renderer")
		return RendererProcess;
#if defined(OS_LINUX)
	else if (process_type == "zygote")
		return ZygoteProcess;
#endif
	return OtherProcess;
}

void WebviewApp::OnBeforeCommandLineProcessing(const CefString &process_type, CefRefPtr<CefCommandLine> command_line)
{
    // Pass additional command-line flags to the browser process.
	if (process_type.empty())
	{
#ifndef WEBVIEW_CEF_GPU_TEXTURE
		// The GPU shared-texture path (OnAcceleratedPaint) requires the GPU
		// compositor; only allow disabling the GPU when it is not compiled in.
		if (!m_bEnableGPU)
		{
			command_line->AppendSwitch("disable-gpu");
			command_line->AppendSwitch("disable-gpu-compositing");
		}
#endif

		// Don't create a "GPUCache" directory when cache-path is unspecified.
		command_line->AppendSwitch("disable-gpu-shader-disk-cache");                            //disable gpu shader disk cache

		//http://www.chromium.org/developers/design-documents/process-models
		if (m_uMode == 1)
		{
			command_line->AppendSwitch("process-per-site");                                     //each site in its own process
			command_line->AppendSwitchWithValue("renderer-process-limit", "8");              //limit renderer process count to decrease memory usage
		}
		else if (m_uMode == 2)
		{
			command_line->AppendSwitch("process-per-tab");                                      //each tab in its own process
		}
		else if (m_uMode == 3)
		{
			command_line->AppendSwitch("single-process");                                     //all in one process
		}
		command_line->AppendSwitchWithValue("autoplay-policy", "no-user-gesture-required");     //autoplay policy for media

        // Keep Chromium's web security, SameSite cookie policy and certificate
        // validation at their normal defaults. A banking container must behave
        // like Chromium, not like a permissive test harness.
        std::string values = command_line->GetSwitchValue("disable-features");
        if (values.find("CalculateNativeWinOcclusion") == size_t(-1))
        {
            if (!values.empty()) values += ",";
            values += "CalculateNativeWinOcclusion";
        }

        command_line->AppendSwitchWithValue("disable-features", values);
    }

#ifdef __APPLE__
    command_line->AppendSwitch("use-mock-keychain");
    // macOS now runs multi-process via bundled CEF helper apps (see the
    // example Runner's "Embed CEF Helpers" phase). The process model is
    // selected by m_uMode above, like the other platforms.
#endif
#ifdef __linux__
                                           
#endif
}

void WebviewApp::OnContextInitialized()
{
    CEF_REQUIRE_UI_THREAD();
//    CefBrowserSettings browser_settings;
//    browser_settings.windowless_frame_rate = 60;
//                
//    CefWindowInfo window_info;
//    window_info.SetAsWindowless(0);
//
//    // create browser
//    CefBrowserHost::CreateBrowser(window_info, m_handler, "", browser_settings, nullptr, nullptr);
    
}

// CefRefPtr<CefClient> WebviewApp::GetDefaultClient() {
//     // Called when a new browser window is created via the Chrome runtime UI.
//     return WebviewHandler::GetInstance();
// }

void WebviewApp::SetUnSafelyTreatInsecureOriginAsSecure(const CefString &strFilterDomain)
{
    m_strFilterDomain = strFilterDomain;
}

void WebviewApp::OnWebKitInitialized()
{
    // Keep the renderer callback surface deliberately tiny. It exists only so
    // the already bounded Dart evaluateJavascript API can receive a result;
    // no storage, cookie, network, navigation or financial operation is
    // exposed to the page.
    if (!m_render_js_bridge.get()) {
        m_render_js_bridge.reset(new CefJSBridge);
    }
    const char extensionCode[] = R"(
      var qestoExternal = {};
      qestoExternal.EvaluateCallback = function(callbackId, result) {
        native function EvaluateCallback();
        return EvaluateCallback(callbackId, result);
      };
      qestoExternal.JavaScriptChannel = function(name, event, result) {
        native function JavaScriptChannel();
        return JavaScriptChannel(name, event, result);
      };
    )";
    CefRefPtr<CefJSHandler> handler = new CefJSHandler;
    handler->AttachJSBridge(m_render_js_bridge);
    CefRegisterExtension("qesto/renderer-callbacks", extensionCode, handler);
}

void WebviewApp::OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> extra_info)
{
    if (!m_render_js_bridge.get()) {
        m_render_js_bridge.reset(new CefJSBridge);
    }
}

void WebviewApp::SetProcessMode(uint32_t uMode)
{
    m_uMode = uMode;
}

void WebviewApp::SetEnableGPU(bool bEnable)
{
    m_bEnableGPU = bEnable;
}

void WebviewApp::OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line)
{
}

void WebviewApp::OnBrowserDestroyed(CefRefPtr<CefBrowser> browser)
{
}

void WebviewApp::OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context)
{
}

void WebviewApp::OnContextReleased(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context)
{
    if (m_render_js_bridge.get())
    {
        m_render_js_bridge->RemoveCallbackFuncWithFrame(frame);
    }
}

void WebviewApp::OnUncaughtException(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context, CefRefPtr<CefV8Exception> exception, CefRefPtr<CefV8StackTrace> stackTrace)
{
}

void WebviewApp::OnFocusedNodeChanged(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefDOMNode> node)
 {    
    //Get node attribute
    bool is_editable = (node.get() && node->IsEditable());
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kFocusedNodeChangedMessage);
    message->GetArgumentList()->SetBool(0, is_editable);
    if (is_editable)
    {
        CefRect rect = node->GetElementBounds();
        message->GetArgumentList()->SetInt(1, rect.x);
        message->GetArgumentList()->SetInt(2, rect.y + rect.height);
        message->GetArgumentList()->SetInt(3, rect.height);
    }
    frame->SendProcessMessage(PID_BROWSER, message);
}

bool WebviewApp::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId source_process, CefRefPtr<CefProcessMessage> message)
{
    const CefString& message_name = message->GetName();
    if (message_name == kExecuteJsCallbackMessage)
    {
        int			callbackId = message->GetArgumentList()->GetInt(0);
        bool		error = message->GetArgumentList()->GetBool(1);
        CefString	result = message->GetArgumentList()->GetString(2);
        if (m_render_js_bridge.get())
        {
            m_render_js_bridge->ExecuteJSCallbackFunc(callbackId, error, result);
        }
    }

    return false;
}
