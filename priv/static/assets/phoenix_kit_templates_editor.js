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
