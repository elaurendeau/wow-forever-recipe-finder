// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Browsers never let a script set an <input type="file">'s path (for any
// site, cookies included — it's a security restriction, not something
// this app can opt out of). The closest real equivalent to "remember my
// file for me" is caching the export's own contents client-side, so a
// revisit skips re-uploading entirely rather than pre-filling a picker.
const SNAPSHOT_KEY = "rf_tsm_export"
const CAPTURED_AT_KEY = "rf_tsm_captured_at"

const Hooks = {
  TsmSnapshot: {
    mounted() {
      let data, capturedAt
      try {
        data = localStorage.getItem(SNAPSHOT_KEY)
        capturedAt = localStorage.getItem(CAPTURED_AT_KEY)
      } catch (_e) {
        data = null
      }
      if (data) this.pushEvent("restore_snapshot", {data, captured_at: capturedAt})

      this.handleEvent("store_snapshot", ({data, captured_at}) => {
        try {
          localStorage.setItem(SNAPSHOT_KEY, data)
          localStorage.setItem(CAPTURED_AT_KEY, captured_at)
        } catch (_e) {
          // Storage full or unavailable (private browsing, quota) — the
          // upload itself already succeeded, so just skip persisting it.
        }
      })

      this.handleEvent("clear_snapshot", () => {
        try {
          localStorage.removeItem(SNAPSHOT_KEY)
          localStorage.removeItem(CAPTURED_AT_KEY)
        } catch (_e) {
          // Nothing to clean up if storage was never writable.
        }
      })
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

