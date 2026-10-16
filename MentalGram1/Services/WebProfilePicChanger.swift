import UIKit
import WebKit

/// Changes the profile picture through the real instagram.com /accounts/edit/ page in a
/// hidden WKWebView that shares the login cookies. Instagram's own JavaScript builds the
/// upload and the PolarisUserActionSetProfilePicMutation (with its per-deploy __dyn/__csr/
/// __rev fields); hand-built copies of those requests are rejected as spam.
@MainActor
final class WebProfilePicChanger: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Outcome {
        case success(profilePicURL: String?)
        /// Instagram answered and refused (Try Again Later / feedback_required).
        case rejected(String)
        /// The page flow could not run (logged out, UI changed, timeout) — nothing was refused.
        case unavailable(String)
    }

    private var lines: [String] = []
    private var outcome: Outcome?
    private var pageLoaded = false

    static func change(jpegData: Data, log: @escaping (String) -> Void = { print($0) }) async -> Outcome {
        await WebProfilePicChanger().execute(jpegData: jpegData, log: log)
    }

    private func execute(jpegData: Data, log: (String) -> Void) async -> Outcome {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(self, name: "pp")
        config.userContentController.addUserScript(WKUserScript(source: Self.hookScript,
                                                                injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: false))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        web.navigationDelegate = self
        // Must be in a window or WebKit throttles the page's timers.
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .addSubview(web)
        defer {
            web.stopLoading()
            web.removeFromSuperview()
            config.userContentController.removeScriptMessageHandler(forName: "pp")
        }

        let started = Date()
        web.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/edit/")!))
        for _ in 0..<60 where !pageLoaded { try? await Task.sleep(nanoseconds: 250_000_000) }

        var state = ""
        for _ in 0..<40 {
            state = (try? await web.evaluateJavaScript(Self.stateScript)) as? String ?? ""
            if state.contains("\"Change photo\"") || state.contains("\"Cambiar foto\"") || state.contains("/accounts/login") { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        log("🌐 [PP-WEB] page ready in \(Int(Date().timeIntervalSince(started)))s: \(state.prefix(300))")
        if state.contains("/accounts/login") {
            return .unavailable("web session logged out")
        }

        let pick = (try? await web.callAsyncJavaScript(Self.pickScript, arguments: ["b64": jpegData.base64EncodedString()],
                                                       contentWorld: .page)) as? String ?? "script error"
        log("🌐 [PP-WEB] flow: \(pick)")
        if !pick.hasPrefix("file fed") && outcome == nil {
            return .unavailable("page flow: \(pick.prefix(160))")
        }

        for _ in 0..<120 where outcome == nil { try? await Task.sleep(nanoseconds: 250_000_000) }
        lines.forEach(log)
        log("🌐 [PP-WEB] finished in \(Int(Date().timeIntervalSince(started)))s")
        return outcome ?? .unavailable("no response to the profile-picture mutation")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { pageLoaded = true }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let url = body["url"] as? String ?? ""
        let status = body["status"] as? Int ?? 0
        let text = (body["text"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
        let compact = text.replacingOccurrences(of: " ", with: "")
        lines.append("🌐 [PP-WEB] \(body["method"] as? String ?? "") \(url.prefix(120)) → \(status): \(text.prefix(300))")

        if url.contains("rupload"), status != 200 {
            outcome = .rejected("upload HTTP \(status): \(text.prefix(200))")
            return
        }
        let isMutation = compact.contains("xig_web_set_profile_picture") || url.contains("change_profile_pic")
            || (body["req"] as? String ?? "").contains("SetProfilePic")
        guard isMutation else { return }
        if compact.contains("\"xig_web_set_profile_picture\":{") || compact.contains("\"changed_profile\":true") {
            outcome = .success(profilePicURL: Self.profilePicURL(in: text))
        } else if compact.contains("feedback_required") || compact.contains("TryAgainLater") || compact.contains("\"spam\":true") {
            outcome = .rejected(String(text.prefix(300)))
        } else {
            outcome = .rejected("mutation HTTP \(status): \(text.prefix(300))")
        }
    }

    private static func profilePicURL(in text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["data"] as? [String: Any])?["xig_web_set_profile_picture"] as? [String: Any],
              let user = result["user"] as? [String: Any] else { return nil }
        return user["profile_pic_url"] as? String
    }

    private static let stateScript = """
    (function(){
      var btns = Array.from(document.querySelectorAll('button,[role=button]')).map(b => b.innerText.trim()).filter(t => t).slice(0, 12);
      return location.href + ' | buttons:' + JSON.stringify(btns);
    })()
    """

    private static let pickScript = """
    function sleep(ms){ return new Promise(r => setTimeout(r, ms)); }
    function buttons(){ return Array.from(document.querySelectorAll('button,[role=button]')).filter(b => b.innerText && b.innerText.trim()); }
    function find(re){ return buttons().find(b => re.test(b.innerText.trim())); }
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const file = new File([bytes], 'IMG_' + Date.now() + '.jpg', { type: 'image/jpeg', lastModified: Date.now() });
    let steps = [];
    let fed = false;
    // Instagram opens the photo picker with input.click(); hand it the file instead.
    const origClick = HTMLInputElement.prototype.click;
    HTMLInputElement.prototype.click = function(){
      if (this.type !== 'file') return origClick.apply(this, arguments);
      const dt = new DataTransfer();
      dt.items.add(file);
      this.files = dt.files;
      this.dispatchEvent(new Event('input', { bubbles: true }));
      this.dispatchEvent(new Event('change', { bubbles: true }));
      fed = true;
      steps.push('picker');
    };
    const dismiss = find(/^(not now|ahora no)$/i);
    if (dismiss) { dismiss.click(); steps.push('dismissed dialog'); await sleep(600); }
    const opener = find(/^(change photo|cambiar foto)$/i);
    if (!opener) return 'no Change photo button; buttons=' + JSON.stringify(buttons().map(b => b.innerText.trim()).slice(0, 15));
    opener.click();
    steps.push('Change photo');
    for (let i = 0; i < 16 && !fed; i++) {
      const upload = find(/^(upload photo|subir foto)$/i);
      if (upload) { upload.click(); steps.push('Upload Photo'); break; }
      await sleep(250);
    }
    for (let i = 0; i < 40 && !location.pathname.startsWith('/create/style'); i++) await sleep(250);
    if (location.pathname.startsWith('/create/style')) {
      let save = null;
      for (let i = 0; i < 24 && !save; i++) { save = find(/^(save|guardar)$/i); if (!save) await sleep(250); }
      const labels = buttons().map(b => b.innerText.trim());
      // A post would need Share/Next; only press Save in the profile-photo editor.
      if (save && !labels.some(t => /^(share|next|compartir|siguiente)$/i.test(t))) { save.click(); steps.push('Save'); }
      else steps.push('editor buttons=' + JSON.stringify(labels.slice(0, 15)));
    }
    return (fed ? 'file fed' : 'file NOT fed') + ' (' + bytes.length + ' bytes): ' + steps.join(' → ');
    """

    private static let hookScript = """
    (function(){
      function interesting(u){ return /rupload|profile_pic|graphql/i.test(u) && !/get_profile_pic_props/i.test(u); }
      function post(m){ try { window.webkit.messageHandlers.pp.postMessage(m); } catch(e){} }
      function describe(body){ if (typeof body === 'string') return body; if (body instanceof URLSearchParams) return body.toString(); return ''; }
      function wanted(url, req){ return /rupload|change_profile_pic/i.test(url) || /SetProfilePic/.test(req); }
      const origFetch = window.fetch;
      window.fetch = async function(input, init){
        const url = typeof input === 'string' ? input : (input && input.url) || '';
        const req = describe(init && init.body);
        const res = await origFetch.apply(this, arguments);
        if (interesting(url) && wanted(url, req)) { res.clone().text().then(t => post({method:(init&&init.method)||'GET', url, status:res.status, req:req.slice(-400), text:t.slice(0,1500)})); }
        return res;
      };
      const open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m, u){ this.__pp = {method:m, url:u}; return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function(body){
        const info = this.__pp || {}; const req = describe(body);
        if (interesting(info.url || '') && wanted(info.url || '', req)) {
          this.addEventListener('loadend', () => post({method:info.method, url:info.url, status:this.status, req:req.slice(-400), text:String(this.responseText || '').slice(0,1500)}));
        }
        return send.apply(this, arguments);
      };
    })();
    """
}
