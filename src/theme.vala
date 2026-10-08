// Dark + orange theme

using Gtk;

// ---------------------------------------------------------------- theme
// Dark mode in the colours of the logo: orange #ff6a00 and the blue dot #0a84ff.

const string THEME_CSS = """
window, window.background, .background {
    background-color: #120e0b;
    color: #f3e9e0;
}

/* header bar with a thin orange line underneath */
headerbar {
    background-image: none;
    background-color: #1a1410;
    color: #f3e9e0;
    border-bottom: 1px solid #ff6a00;
    box-shadow: none;
}
headerbar button {
    background-color: transparent;
    border-color: transparent;
}
headerbar button:hover {
    background-color: #33261d;
}

/* logo in the header bar */
.app-logo {
    border-radius: 8px;
    overflow: hidden;
}

/* buttons */
button {
    background-image: none;
    background-color: #251c16;
    color: #f3e9e0;
    border: 1px solid #3f2e22;
    box-shadow: none;
    text-shadow: none;
}
button:hover {
    background-color: #33261d;
    border-color: #ff6a00;
}
button:active,
button:checked,
stackswitcher button:checked {
    background-color: #ff6a00;
    border-color: #ff6a00;
    color: #120e0b;
}
button.suggested-action {
    background-color: #ff6a00;
    border-color: #ff6a00;
    color: #120e0b;
}
button.suggested-action:hover {
    background-color: #ff8533;
    border-color: #ff8533;
}

/* entries and spin buttons */
entry, spinbutton, passwordentry {
    background-color: #251c16;
    color: #f3e9e0;
    border: 1px solid #3f2e22;
    box-shadow: none;
}
entry:focus-within, spinbutton:focus-within, passwordentry:focus-within {
    border-color: #ff6a00;
    outline-color: rgba(255, 106, 0, 0.5);
}
spinbutton button {
    background-color: transparent;
    border-color: transparent;
}

/* lists */
list, listview {
    background-color: #17110d;
    color: #f3e9e0;
}
row {
    border-bottom: 1px solid #261c15;
}
row:hover {
    background-color: #251c16;
}
row:selected {
    background-color: #43200b;
    color: #fff3ea;
    box-shadow: inset 3px 0 0 #ff6a00;
}
row:selected .dim-label {
    color: #e0b99c;
}

/* separators and the divider between list and detail */
separator {
    background-color: #3f2e22;
}

/* orange line between days in the appointments list */
.day-divider {
    background-color: #ff6a00;
    min-height: 2px;
    margin-top: 6px;
    margin-bottom: 6px;
}
paned > separator {
    background-color: #3f2e22;
    background-image: none;
}

/* text */
.dim-label {
    color: #a99686;
    opacity: 1;
}
label.heading {
    color: #ff9a4d;
}
.monospace {
    color: #ffb27a;
}
link, label link, *:link {
    color: #4da3ff;
}
selection, label selection, text selection {
    background-color: #ff6a00;
    color: #120e0b;
}
expander title arrow {
    color: #ff6a00;
}

/* scrollbars */
scrollbar slider {
    background-color: #5a4232;
}
scrollbar slider:hover {
    background-color: #ff6a00;
}

/* tooltips */
tooltip, tooltip.background {
    background-color: #251c16;
    color: #f3e9e0;
    border: 1px solid #ff6a00;
}
""";

void apply_dark_orange_theme () {
    // make everything the CSS doesn't cover (dialog internals, etc.) dark too
    var settings = Gtk.Settings.get_default ();
    if (settings != null) settings.gtk_application_prefer_dark_theme = true;

    var provider = new Gtk.CssProvider ();
    provider.load_from_string (THEME_CSS);   // GTK 4.12+; see note for older GTK
    Gtk.StyleContext.add_provider_for_display (
        Gdk.Display.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
}
