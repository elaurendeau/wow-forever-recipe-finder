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
// A visitor's chosen realm (per the top-right realm selector, shared
// across every page) — kept separate from the snapshot blob above
// since switching realms shouldn't re-save the whole multi-hundred-KB
// export text, only this small string.
const REALM_KEY = "rf_tsm_realm"

const Hooks = {
  TsmSnapshot: {
    mounted() {
      let data, capturedAt, realm
      try {
        data = localStorage.getItem(SNAPSHOT_KEY)
        capturedAt = localStorage.getItem(CAPTURED_AT_KEY)
        realm = localStorage.getItem(REALM_KEY)
      } catch (_e) {
        data = null
      }
      if (data) this.pushEvent("restore_snapshot", {data, captured_at: capturedAt, realm})

      this.handleEvent("store_snapshot", ({data, captured_at}) => {
        try {
          localStorage.setItem(SNAPSHOT_KEY, data)
          localStorage.setItem(CAPTURED_AT_KEY, captured_at)
        } catch (_e) {
          // Storage full or unavailable (private browsing, quota) — the
          // upload itself already succeeded, so just skip persisting it.
        }
      })

      this.handleEvent("store_realm", ({realm}) => {
        try {
          localStorage.setItem(REALM_KEY, realm)
        } catch (_e) {
          // Storage full or unavailable — the selection still applies
          // for this page view, it just won't follow to another page.
        }
      })

      this.handleEvent("clear_snapshot", () => {
        try {
          localStorage.removeItem(SNAPSHOT_KEY)
          localStorage.removeItem(CAPTURED_AT_KEY)
          localStorage.removeItem(REALM_KEY)
        } catch (_e) {
          // Nothing to clean up if storage was never writable.
        }
      })
    }
  },

  CopyButton: {
    mounted() {
      this.el.addEventListener("click", () => {
        const text = this.el.dataset.copy
        const original = this.el.textContent

        const done = () => {
          this.el.textContent = "Copied!"
          setTimeout(() => { this.el.textContent = original }, 1500)
        }

        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done).catch(() => this.fallbackCopy(text, done))
        } else {
          this.fallbackCopy(text, done)
        }
      })
    },
    fallbackCopy(text, done) {
      // document.execCommand is deprecated but still the only option
      // when the async Clipboard API isn't available (older browsers,
      // or a non-secure context).
      const textarea = document.createElement("textarea")
      textarea.value = text
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.focus()
      textarea.select()
      try {
        document.execCommand("copy")
      } catch (_e) {
        // Nothing more we can do — the user can still select the text by hand.
      }
      document.body.removeChild(textarea)
      done()
    }
  },

  HoverTooltip: {
    // Positioned with position: fixed, computed here rather than via CSS
    // position: absolute, because the table's wrapper sets overflow-x:
    // auto — which per spec forces overflow-y to auto too, clipping an
    // absolutely-positioned child near the top/bottom of the table.
    // Fixed positioning escapes that ancestor's overflow entirely.
    mounted() {
      const tooltip = this.el.querySelector(".rf-tooltip")
      if (!tooltip) return

      this.el.addEventListener("mouseenter", () => {
        tooltip.style.display = "block"
        const trigger = this.el.getBoundingClientRect()
        const tw = tooltip.offsetWidth
        const th = tooltip.offsetHeight
        let left = trigger.right - tw
        let top = trigger.top - th - 6

        if (top < 4) top = trigger.bottom + 6
        if (left < 4) left = 4
        if (left + tw > window.innerWidth - 4) left = window.innerWidth - tw - 4

        tooltip.style.left = `${left}px`
        tooltip.style.top = `${top}px`
      })

      this.el.addEventListener("mouseleave", () => {
        tooltip.style.display = "none"
      })
    }
  }
}

// Writ Route Map (docs/PRD.md § 7.10). The server renders the SVG once
// with the whole-canvas viewBox; zoom/pan live here so they survive
// every filter/pin-selection patch. `updated()` re-applies the current
// viewBox because a LiveView patch would otherwise reset it to the
// server-rendered one. `--k` (canvas units per screen pixel) keeps
// pins and labels a constant on-screen size at any zoom — see
// .rf-map-scaled / .rf-map-zone-label in app.css.
const MIN_VIEW_WIDTH = 1500
const MAX_VIEW_WIDTH = 60000

Hooks.WritMap = {
  mounted() {
    this.viewBox = this.el.getAttribute("viewBox").split(/\s+/).map(Number)
    this.card = this.el.closest(".rf-map-card")
    this.drag = null

    this.el.addEventListener("wheel", (e) => {
      e.preventDefault()
      const p = this.toCanvas(e)
      this.zoomAt(e.deltaY > 0 ? 1.2 : 1 / 1.2, p.x, p.y)
    }, {passive: false})

    this.el.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return
      this.drag = {x: e.clientX, y: e.clientY, start: this.viewBox.slice(), moved: false}
      this.el.classList.add("dragging")
    })
    this.onMove = (e) => {
      if (!this.drag) return
      const k = this.scale()
      const dx = (e.clientX - this.drag.x) * k
      const dy = (e.clientY - this.drag.y) * k
      if (Math.abs(e.clientX - this.drag.x) + Math.abs(e.clientY - this.drag.y) > 3) this.drag.moved = true
      this.viewBox = [this.drag.start[0] - dx, this.drag.start[1] - dy, this.viewBox[2], this.viewBox[3]]
      this.el.setAttribute("viewBox", this.viewBox.join(" "))
    }
    this.onUp = () => {
      if (!this.drag) return
      this.suppressClick = this.drag.moved
      this.drag = null
      this.el.classList.remove("dragging")
    }
    window.addEventListener("pointermove", this.onMove)
    window.addEventListener("pointerup", this.onUp)

    // A drag that ends over a pin must not also select it.
    this.el.addEventListener("click", (e) => {
      if (this.suppressClick) {
        e.stopPropagation()
        e.preventDefault()
      }
      this.suppressClick = false
    }, true)

    this.card.querySelectorAll("[data-zoom]").forEach((button) => {
      button.addEventListener("click", () => {
        const [x, y, w, h] = this.viewBox
        this.zoomAt(button.dataset.zoom === "in" ? 1 / 1.5 : 1.5, x + w / 2, y + h / 2)
      })
    })

    // Dispatched by the continent-shortcut buttons via JS.dispatch — a
    // plain view change, no server round-trip needed for it.
    this.el.addEventListener("rf:map-show-view", (e) => {
      this.viewBox = e.detail.view_box.split(/\s+/).map(Number)
      this.apply()
    })

    this.resizeObserver = new ResizeObserver(() => this.apply())
    this.resizeObserver.observe(this.el)
    this.apply()
  },

  updated() { this.apply() },

  destroyed() {
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
    this.resizeObserver.disconnect()
  },

  apply() {
    this.el.setAttribute("viewBox", this.viewBox.join(" "))
    this.el.style.setProperty("--k", this.scale())
  },

  // preserveAspectRatio="xMidYMid meet": the larger ratio wins.
  scale() {
    const r = this.el.getBoundingClientRect()
    return Math.max(this.viewBox[2] / (r.width || 1), this.viewBox[3] / (r.height || 1))
  },

  zoomAt(factor, cx, cy) {
    const [x, y, w, h] = this.viewBox
    const nw = Math.min(Math.max(w * factor, MIN_VIEW_WIDTH), MAX_VIEW_WIDTH)
    const nh = nw * h / w
    this.viewBox = [cx - (cx - x) * nw / w, cy - (cy - y) * nh / h, nw, nh]
    this.apply()
  },

  toCanvas(e) {
    const pt = this.el.createSVGPoint()
    pt.x = e.clientX
    pt.y = e.clientY
    return pt.matrixTransform(this.el.getScreenCTM().inverse())
  }
}

// Flashes a writ row's matching map pin on hover, entirely client-side
// (no server round-trip — hover fires far too often for that, and the
// pin's own position never changes based on hover). One delegated
// listener on the table body rather than one per row.
Hooks.WritRowHover = {
  mounted() {
    this.onOver = (e) => {
      const row = e.target.closest("tr[data-pin-id]")
      if (!row || !row.dataset.pinId) return
      const pin = document.getElementById(`wm-pin-${row.dataset.pinId}`)
      if (pin) pin.classList.add("hovered")
    }
    this.onOut = (e) => {
      const row = e.target.closest("tr[data-pin-id]")
      if (!row || !row.dataset.pinId) return
      const pin = document.getElementById(`wm-pin-${row.dataset.pinId}`)
      if (pin) pin.classList.remove("hovered")
    }
    this.el.addEventListener("mouseover", this.onOver)
    this.el.addEventListener("mouseout", this.onOut)
  },
  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver)
    this.el.removeEventListener("mouseout", this.onOut)
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

