// phoenix_kit_templates_editor JS hooks — folded into the host's LiveSocket
// by core's :phoenix_kit_js_sources compiler (PhoenixKit.Module.js_sources/0).
// No build step: this file is the bundle.
//
// PhoenixKitTemplatesEditorInsertVariable sits on the element around the
// editor's form and its variables panel. A panel button carries the
// placeholder in data-variable; with this hook a click puts it where the
// cursor was in the field last typed in, without a round trip. Without the
// hook (or before any field had the focus) the button submits the form and
// the server puts the placeholder at the end of the body.
(function () {
  "use strict";

  window.PhoenixKitTemplatesEditorHooks = window.PhoenixKitTemplatesEditorHooks || {};
  if (window.PhoenixKitTemplatesEditorHooks.PhoenixKitTemplatesEditorInsertVariable) return;

  window.PhoenixKitTemplatesEditorHooks.PhoenixKitTemplatesEditorInsertVariable = {
    mounted() {
      this._field = null;
      this._start = 0;
      this._end = 0;

      this._track = (event) => {
        var field = event.target;
        if (!field || field.tagName !== "TEXTAREA" || !this.el.contains(field)) return;
        this._field = field;
        this._start = field.selectionStart;
        this._end = field.selectionEnd;
      };

      this._insert = (event) => {
        var button = event.target.closest("button[data-variable]");
        if (!button || !this.el.contains(button)) return;

        var field = this._field;
        // The field may have been redrawn since; then the server does it.
        if (!field || !document.body.contains(field)) return;

        event.preventDefault();
        event.stopPropagation();

        var text = button.dataset.variable;
        var start = Math.min(this._start, field.value.length);
        var end = Math.min(Math.max(this._end, start), field.value.length);

        field.value = field.value.slice(0, start) + text + field.value.slice(end);
        var position = start + text.length;
        field.focus();
        field.setSelectionRange(position, position);
        this._start = this._end = position;
        field.dispatchEvent(new Event("input", { bubbles: true }));
      };

      ["focusin", "keyup", "click", "select"].forEach((type) => {
        this.el.addEventListener(type, this._track);
      });
      // Capture: before LiveView's own click handling submits the form.
      this.el.addEventListener("click", this._insert, true);
    },

    destroyed() {
      ["focusin", "keyup", "click", "select"].forEach((type) => {
        this.el.removeEventListener(type, this._track);
      });
      this.el.removeEventListener("click", this._insert, true);
    }
  };
})();

// PhoenixKitTemplatesEditorKeepFocus sits on the variables list of a letter.
// A button with data-keep-focus does not take the focus on mousedown, so the
// caret of the Leaf editor is still where it was when the click arrives (an
// inline onmousedown would be refused by a strict script-src).
(function () {
  "use strict";

  window.PhoenixKitTemplatesEditorHooks = window.PhoenixKitTemplatesEditorHooks || {};
  if (window.PhoenixKitTemplatesEditorHooks.PhoenixKitTemplatesEditorKeepFocus) return;

  window.PhoenixKitTemplatesEditorHooks.PhoenixKitTemplatesEditorKeepFocus = {
    mounted() {
      this._keep = (event) => {
        var target = event.target;
        if (target && target.closest && target.closest("button[data-keep-focus]")) {
          event.preventDefault();
        }
      };
      this.el.addEventListener("mousedown", this._keep);
    },

    destroyed() {
      this.el.removeEventListener("mousedown", this._keep);
    }
  };
})();

// PhoenixKitTemplatesEditorFolds sits on the list of templates. Its sections
// fold (<details>); which of them the reader left open is kept in this
// browser, so the list opens the way it was left. The section holding the
// open template is always shown open.
(function () {
  "use strict";

  window.PhoenixKitTemplatesEditorHooks = window.PhoenixKitTemplatesEditorHooks || {};
  if (window.PhoenixKitTemplatesEditorHooks.PhoenixKitTemplatesEditorFolds) return;

  var KEY = "phoenix_kit_templates_editor:folds";

  function read() {
    try {
      return JSON.parse(window.localStorage.getItem(KEY) || "{}") || {};
    } catch (_error) {
      return {};
    }
  }

  function write(state) {
    try {
      window.localStorage.setItem(KEY, JSON.stringify(state));
    } catch (_error) {
      // Private mode, a full store: the list just opens on its defaults.
    }
  }

  window.PhoenixKitTemplatesEditorHooks.PhoenixKitTemplatesEditorFolds = {
    mounted() {
      this._seen = {};
      this._restore();

      // `toggle` does not bubble: caught on the way down.
      this._toggle = (event) => {
        var section = event.target;
        if (!section || section.tagName !== "DETAILS" || !section.id) return;
        var state = read();
        state[section.id] = section.open;
        write(state);
      };
      this.el.addEventListener("toggle", this._toggle, true);
    },

    // A re-render can bring a section the list had none of (a layout group
    // that appeared, a list that was empty): it is drawn on its defaults, so
    // the kept state is applied to it — once; a section already seen keeps
    // what the reader did with it since.
    updated() {
      this._restore();
    },

    _restore() {
      var saved = read();

      this.el.querySelectorAll("details[id]").forEach((section) => {
        if (this._seen[section.id]) return;
        this._seen[section.id] = true;

        if (Object.prototype.hasOwnProperty.call(saved, section.id)) {
          section.open = saved[section.id] === true;
        }
        if (section.querySelector(".menu-active")) section.open = true;
      });
    },

    destroyed() {
      this.el.removeEventListener("toggle", this._toggle, true);
    }
  };
})();
