using Gtk;

// ---------------------------------------------------------------- helpers

string jstr (Json.Object? o, string key) {
    if (o == null) return "";
    string k = key;
    if (!o.has_member (k)) {
        k = key.substring (0, 1).up () + key.substring (1);
        if (!o.has_member (k)) return "";
    }
    var n = o.get_member (k);
    if (n.get_node_type () != Json.NodeType.VALUE) return "";
    return n.get_string () ?? "";
}

Json.Object? jobj (Json.Object? o, string key) {
    if (o == null) return null;
    string k = key;
    if (!o.has_member (k)) {
        k = key.substring (0, 1).up () + key.substring (1);
        if (!o.has_member (k)) return null;
    }
    var n = o.get_member (k);
    return n.get_node_type () == Json.NodeType.OBJECT ? n.get_object () : null;
}

Json.Array? items_of_node (Json.Node? n) {
    if (n == null) return null;
    if (n.get_node_type () == Json.NodeType.ARRAY) return n.get_array ();
    if (n.get_node_type () == Json.NodeType.OBJECT) {
        var o = n.get_object ();
        string k = o.has_member ("items") ? "items" : (o.has_member ("Items") ? "Items" : "");
        if (k != "") {
            var i = o.get_member (k);
            if (i.get_node_type () == Json.NodeType.ARRAY) return i.get_array ();
        }
    }
    return null;
}

Json.Array? jarr (Json.Object? o, string key) {
    if (o == null) return null;
    string k = key;
    if (!o.has_member (k)) {
        k = key.substring (0, 1).up () + key.substring (1);
        if (!o.has_member (k)) return null;
    }
    return items_of_node (o.get_member (k));
}

// href of the link with the given rel in a "links": [{rel, href}] array
string link_href (Json.Object? o, string rel) {
    var links = jarr (o, "links");
    if (links == null) return "";
    for (uint i = 0; i < links.get_length (); i++) {
        var l = links.get_object_element (i);
        if (jstr (l, "rel").down () == rel.down ()) return jstr (l, "href");
    }
    return "";
}

string names (Json.Object o, string key, string f1, string f2 = "") {
    var arr = jarr (o, key);
    if (arr == null) return "";
    var sb = new StringBuilder ();
    for (uint i = 0; i < arr.get_length (); i++) {
        var e = arr.get_element (i);
        if (e.get_node_type () != Json.NodeType.OBJECT) continue;
        var eo = e.get_object ();
        string s = jstr (eo, f1);
        if (s == "" && f2 != "") s = jstr (eo, f2);
        if (s == "") continue;
        if (sb.len > 0) sb.append (", ");
        sb.append (s);
    }
    return sb.str;
}

string fmt_time (string iso, bool full = true) {
    if (iso == "") return "";
    DateTime? dt = new DateTime.from_iso8601 (iso, null);
    if (dt == null)
        return iso.length >= 16 ? iso.substring (0, 16).replace ("T", " ") : iso;
    return dt.to_local ().format (full ? "%a %d %b %H:%M" : "%H:%M");
}

string fmt_date (string iso) {
    if (iso == "") return "";
    DateTime? dt = new DateTime.from_iso8601 (iso, null);
    if (dt == null) return iso.length >= 10 ? iso.substring (0, 10) : iso;
    return dt.to_local ().format ("%d %b %Y");
}

string strip_html (string html) {
    try {
        var s = html;
        s = new Regex ("<\\s*(br|/p|/div|/li|/tr|/h[1-6])\\s*/?>", RegexCompileFlags.CASELESS).replace (s, -1, 0, "\n");
        s = new Regex ("<[^>]*>").replace (s, -1, 0, "");
        s = s.replace ("&nbsp;", " ").replace ("&lt;", "<").replace ("&gt;", ">")
             .replace ("&quot;", "\"").replace ("&#39;", "'").replace ("&amp;", "&");
        s = new Regex ("\\n{3,}").replace (s, -1, 0, "\n\n");
        return s.strip ();
    } catch (RegexError e) {
        return html;
    }
}

string pretty (Json.Node n) {
    var g = new Json.Generator ();
    g.pretty = true;
    g.set_root (n);
    return g.to_data (null);
}

string longest_string (Json.Node n) {
    string best = "";
    if (n.get_node_type () == Json.NodeType.VALUE) {
        if (n.get_value_type () == typeof (string)) return n.get_string () ?? "";
    } else if (n.get_node_type () == Json.NodeType.ARRAY) {
        var a = n.get_array ();
        for (uint i = 0; i < a.get_length (); i++) {
            string c = longest_string (a.get_element (i));
            if (c.length > best.length) best = c;
        }
    } else if (n.get_node_type () == Json.NodeType.OBJECT) {
        var o = n.get_object ();
        o.foreach_member ((obj, name, node) => {
            string c = longest_string (node);
            if (c.length > best.length) best = c;
        });
    }
    return best;
}

string esc (string s) {
    return Markup.escape_text (s);
}

bool is_http (string u) {
    return u.has_prefix ("http://") || u.has_prefix ("https://");
}

// ---------------------------------------------------------------- client

public class Client : Object {
    public string base_url = "http://127.0.0.1:5075";
    public string key = "";
    Soup.Session session = new Soup.Session ();

    public async Bytes get_bytes (string path) throws Error {
        string b = base_url;
        while (b.has_suffix ("/")) b = b.substring (0, b.length - 1);
        var msg = new Soup.Message ("GET", b + path);
        if (msg == null) throw new IOError.FAILED ("Invalid server URL");
        msg.request_headers.append ("Authorization", "Bearer " + key);
        var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
        if (msg.status_code != 200) {
            var data = bytes.get_data ();
            var sb = new StringBuilder ();
            sb.append_len ((string) data, data.length);
            string body = sb.str;
            if (msg.status_code == 401) body = "API key missing or wrong";
            throw new IOError.FAILED ("HTTP %u: %s", msg.status_code, body);
        }
        return bytes;
    }

    public async Json.Node get_json (string path) throws Error {
        var bytes = yield get_bytes (path);
        var data = bytes.get_data ();
        var p = new Json.Parser ();
        p.load_from_data ((string) data, data.length);
        return p.get_root ();
    }

    // any school API path, raw JSON passthrough
    public async Json.Node get_raw (string school_path) throws Error {
        return yield get_json ("/api/raw?path=" + Uri.escape_string (school_path, null, true));
    }
}

// ---------------------------------------------------------------- page base

public abstract class Page : Box {
    protected Client client;
    protected ListBox list = new ListBox ();
    protected Label detail = new Label ("");
    protected Box sections = new Box (Orientation.VERTICAL, 4);
    protected Box files = new Box (Orientation.VERTICAL, 6);
    protected Label raw_label = new Label ("");
    protected Expander raw_exp = new Expander ("Raw JSON");
    protected Label status = new Label ("");
    protected SpinButton spin;
    protected Label spin_lbl = new Label ("");
    protected Json.Node? root_node = null;
    protected Json.Array? items = null;
    protected uint64 gen = 0;   // increases on every selection, to drop stale async results
    bool loaded = false;

    protected abstract string list_path ();
    protected abstract void row_info (Json.Object o, out string title, out string sub,
                                      out string trail, out bool bold);
    protected abstract async void load_detail (Json.Object o) throws Error;

    protected Page (Client c, string spin_label, int def, int min, int max) {
        Object (orientation: Orientation.VERTICAL, spacing: 0);
        client = c;

        // controls
        var controls = new Box (Orientation.HORIZONTAL, 8) {
            margin_top = 8, margin_bottom = 8, margin_start = 12, margin_end = 12
        };
        spin = new SpinButton.with_range (min, max, 1);
        spin.value = def;
        spin_lbl.label = spin_label;
        if (spin_label == "") { spin.visible = false; spin_lbl.visible = false; }
        var go = new Button.with_label ("Refresh");
        go.clicked.connect (() => { refresh.begin (); });
        spin.activate.connect (() => { refresh.begin (); });
        status.xalign = 0;
        status.hexpand = true;
        status.ellipsize = Pango.EllipsizeMode.END;
        status.add_css_class ("dim-label");
        controls.append (spin_lbl);
        controls.append (spin);
        controls.append (go);
        controls.append (status);
        append (controls);
        append (new Separator (Orientation.HORIZONTAL));

        // list (left)
        list.row_selected.connect (on_select);
        var left = new ScrolledWindow () {
            child = list,
            hscrollbar_policy = PolicyType.NEVER,
            width_request = 300
        };

        // detail (right)
        detail.xalign = 0;
        detail.yalign = 0;
        detail.wrap = true;
        detail.wrap_mode = Pango.WrapMode.WORD_CHAR;
        detail.selectable = true;
        detail.use_markup = true;
        raw_label.xalign = 0;
        raw_label.wrap = true;
        raw_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        raw_label.selectable = true;
        raw_label.add_css_class ("monospace");
        raw_exp.child = raw_label;
        raw_exp.visible = false;
        var dbox = new Box (Orientation.VERTICAL, 14) {
            margin_top = 18, margin_bottom = 18, margin_start = 20, margin_end = 20
        };
        dbox.append (detail);
        dbox.append (sections);
        dbox.append (files);
        dbox.append (raw_exp);
        var right = new ScrolledWindow () {
            child = dbox,
            hscrollbar_policy = PolicyType.NEVER,
            hexpand = true
        };

        var paned = new Paned (Orientation.HORIZONTAL) {
            vexpand = true,
            position = 380,
            start_child = left,
            end_child = right,
            shrink_start_child = false,
            resize_start_child = false
        };
        append (paned);
        clear_detail ();
        detail.label = "<i>Select an item</i>";
    }

    public void invalidate () { loaded = false; }

    public void ensure_loaded () {
        if (loaded) return;
        loaded = true;
        refresh.begin ();
    }

    public async void refresh () {
        loaded = true;
        status.label = "Loading…";
        gen++;
        clear_detail ();
        try {
            var node = yield client.get_json (list_path ());
            root_node = node;
            items = items_of_node (root_node);
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            if (items == null) {
                status.label = "Unexpected response from the server";
                show_raw (node);
                return;
            }
            for (uint i = 0; i < items.get_length (); i++) {
                string t, s, tr; bool b;
                row_info (items.get_object_element (i), out t, out s, out tr, out b);
                list.append (make_row (t, s, tr, b));
            }
            status.label = "%u items".printf (items.get_length ());
        } catch (Error e) {
            status.label = "Error: " + e.message;
        }
    }

    Widget make_row (string title, string sub, string trail, bool bold) {
        var box = new Box (Orientation.HORIZONTAL, 12) {
            margin_top = 8, margin_bottom = 8, margin_start = 12, margin_end = 12
        };
        var v = new Box (Orientation.VERTICAL, 2) { hexpand = true };
        var t = new Label (null) {
            xalign = 0f, use_markup = true, ellipsize = Pango.EllipsizeMode.END,
            label = bold ? "<b>" + esc (title) + "</b>" : esc (title)
        };
        v.append (t);
        if (sub != "") {
            var s = new Label (sub) { xalign = 0f, ellipsize = Pango.EllipsizeMode.END };
            s.add_css_class ("dim-label");
            s.add_css_class ("caption");
            v.append (s);
        }
        box.append (v);
        if (trail != "") {
            var tr = new Label (trail) { valign = Align.CENTER };
            tr.add_css_class ("heading");
            box.append (tr);
        }
        return box;
    }

    void on_select (ListBoxRow? row) {
        if (row == null || items == null) return;
        int i = row.get_index ();
        if (i < 0 || i >= (int) items.get_length ()) return;
        var o = items.get_object_element (i);
        gen++;
        clear_detail ();
        detail.label = "<i>Loading…</i>";
        load_detail.begin (o, (obj, res) => {
            try {
                load_detail.end (res);
            } catch (Error e) {
                detail.label = "<span foreground='#ff6b6b'>" + esc (e.message) + "</span>";
            }
        });
    }

    // -------- helpers for subclasses

    protected void clear_detail () {
        Widget? c;
        while ((c = files.get_first_child ()) != null) files.remove (c);
        while ((c = sections.get_first_child ()) != null) sections.remove (c);
        raw_exp.visible = false;
        raw_exp.expanded = false;
        detail.label = "";
    }

    protected void show_raw (Json.Node n) {
        raw_label.label = pretty (n);
        raw_exp.visible = true;
    }

    protected string kv (string k, string v) {
        return v == "" ? "" : "<b>" + esc (k) + "</b>  " + esc (v) + "\n";
    }

    protected string size_label (string size) {
        if (size == "") return "";
        double kb = double.parse (size) / 1024.0;
        if (kb <= 0) return "";
        return kb >= 1024 ? " (%.1f MB)".printf (kb / 1024.0) : " (%.0f KB)".printf (kb);
    }

    // a titled block in the detail pane; returns the box to put its file buttons in
    protected Box add_section (string heading, out Label body) {
        var box = new Box (Orientation.VERTICAL, 6) { margin_top = 10 };
        var h = new Label (null) {
            use_markup = true, xalign = 0f, wrap = true, selectable = true,
            label = "<b>" + esc (heading) + "</b>"
        };
        body = new Label ("") {
            xalign = 0f, wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR,
            selectable = true, visible = false
        };
        var fbox = new Box (Orientation.VERTICAL, 4) { margin_start = 12 };
        box.append (h);
        box.append (body);
        box.append (fbox);
        sections.append (box);
        return fbox;
    }

    protected void add_file_to (Box target, string label, string path, string name, string type) {
        var b = new Button.with_label ("⬇  " + label) { halign = Align.START };
        b.clicked.connect (() => { download.begin (path, name, type); });
        target.append (b);
    }

    protected void add_file (string label, string path, string name, string type) {
        add_file_to (files, label, path, name, type);
    }

    protected void add_link_to (Box target, string label, string url) {
        var b = new Button.with_label ("🔗  " + label) { halign = Align.START };
        b.tooltip_text = url;
        b.clicked.connect (() => { open_uri (url); });
        target.append (b);
    }

    void open_uri (string url) {
        try {
            AppInfo.launch_default_for_uri (url, null);
            status.label = "Opened: " + url;
        } catch (Error e) {
            status.label = "Could not open link: " + e.message;
        }
    }

    // list of message attachments: {"items":[{id,naam,contentType,grootte,links:{download}}]}
    protected void add_bijlagen (Json.Array? bij) {
        if (bij == null) return;
        for (uint i = 0; i < bij.get_length (); i++) {
            var a = bij.get_object_element (i);
            string href = jstr (jobj (jobj (a, "links"), "download"), "href");
            if (href == "") {
                string aid = jstr (a, "id");
                if (aid != "") href = "/api/berichten/bijlagen/" + aid + "/download";
            }
            if (href == "") continue;
            string name = jstr (a, "naam");
            if (name == "") name = "attachment-" + jstr (a, "id");
            add_file (name + size_label (jstr (a, "grootte")), href, name, jstr (a, "contentType"));
        }
    }

    protected async void load_bijlagen (string href, uint64 my) {
        try {
            var bn = yield client.get_raw (href);
            if (my != gen) return;
            add_bijlagen (items_of_node (bn));
        } catch (Error e) {
            if (my != gen) return;
            detail.label += "\n<span foreground='#ff6b6b'>Loading attachments failed: " + esc (e.message) + "</span>";
        }
    }

    string dl_url (string path, string name, string type) {
        string url = "/api/download?path=" + Uri.escape_string (path, null, true);
        if (name != "") url += "&name=" + Uri.escape_string (name, null, true);
        if (type != "") url += "&type=" + Uri.escape_string (type, null, true);
        return url;
    }

    // Some resources answer with JSON metadata instead of the file; find the real location in it.
    string? follow_target (uint8[] data, string current) {
        try {
            var p = new Json.Parser ();
            p.load_from_data ((string) data, data.length);
            var root = p.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
            var o = root.get_object ();
            string next = jstr (o, "uri");
            string h = link_href (o, "Contents");
            if (h == "") h = link_href (o, "Download");
            if (h != "" && h != current) next = h;
            return next == "" ? null : next;
        } catch (Error e) {
            return null;
        }
    }

    async void download (string path, string name, string type) {
        status.label = "Downloading: " + name;
        try {
            var bytes = yield client.get_bytes (dl_url (path, name, type));
            var data = bytes.get_data ();

            if (data.length > 0 && data[0] == '{' && !type.down ().contains ("json")) {
                string? next = follow_target (data, path);
                if (next != null && next != path) {
                    if (is_http (next)) {
                        try {
                            bytes = yield client.get_bytes (dl_url (next, name, type));
                            data = bytes.get_data ();
                        } catch (Error e2) {
                            // an external address: not a file on the school server, show it in the browser
                            open_uri (next);
                            return;
                        }
                    } else {
                        bytes = yield client.get_bytes (dl_url (next, name, type));
                        data = bytes.get_data ();
                    }
                }
            }

            string dir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD) ?? Environment.get_home_dir ();
            string fname = Path.get_basename (name == "" ? "download.bin" : name);
            var f = File.new_for_path (Path.build_filename (dir, fname));
            f.replace_contents (data, null, false, FileCreateFlags.REPLACE_DESTINATION, null, null);
            status.label = "Saved: " + f.get_path ();
            try {
                AppInfo.launch_default_for_uri (f.get_uri (), null);
                status.label = "Opened: " + f.get_path ();
            } catch (Error oe) {
                status.label = "Saved (could not open: " + oe.message + "): " + f.get_path ();
            }
        } catch (Error e) {
            status.label = "Download failed: " + e.message;
        }
    }
}

// ---------------------------------------------------------------- pages

public class AppointmentsPage : Page {
    public AppointmentsPage (Client c) { base (c, "Days", 7, 1, 60); }

    protected override string list_path () {
        return "/api/afspraken?days=%d".printf ((int) spin.value);
    }

    protected override void row_info (Json.Object o, out string title, out string sub,
                                      out string trail, out bool bold) {
        title = jstr (o, "omschrijving");
        if (title == "") title = names (o, "vakken", "naam");
        if (title == "") title = "(appointment)";
        string t = jstr (o, "duurtHeleDag") == "true"
            ? fmt_date (jstr (o, "start")) + " (all day)"
            : fmt_time (jstr (o, "start")) + " – " + fmt_time (jstr (o, "einde"), false);
        string loc = jstr (o, "lokatie");
        if (loc == "") loc = names (o, "lokalen", "naam");
        sub = loc != "" ? t + "  ·  " + loc : t;
        trail = jstr (o, "lesuurVan");
        bold = false;
    }

    protected override async void load_detail (Json.Object o) throws Error {
        uint64 my = gen;
        Json.Object d = o;
        Json.Node? full = null;
        try {
            full = yield client.get_json ("/api/afspraken/" + jstr (o, "id"));
            if (full.get_node_type () == Json.NodeType.OBJECT) d = full.get_object ();
        } catch (Error e) { /* fall back to the list item */ }
        if (my != gen) return;

        string title = jstr (d, "omschrijving");
        if (title == "") title = names (d, "vakken", "naam");
        var sb = new StringBuilder ();
        sb.append ("<span size='x-large' weight='bold'>" + esc (title) + "</span>\n\n");
        sb.append (kv ("Time", fmt_time (jstr (d, "start")) + " – " + fmt_time (jstr (d, "einde"), false)));
        string loc = jstr (d, "lokatie");
        if (loc == "") loc = names (d, "lokalen", "naam");
        sb.append (kv ("Room", loc));
        sb.append (kv ("Period", jstr (d, "lesuurVan")));
        sb.append (kv ("Subject", names (d, "vakken", "naam")));
        sb.append (kv ("Teacher", names (d, "docenten", "naam", "docentcode")));
        string inhoud = strip_html (jstr (d, "inhoud"));
        if (inhoud != "") sb.append ("\n<b>Homework / content</b>\n" + esc (inhoud) + "\n");
        string opm = strip_html (jstr (d, "opmerking"));
        if (opm != "") sb.append ("\n<b>Remark</b>\n" + esc (opm) + "\n");
        detail.label = sb.str;

        var links = jarr (d, "links");
        if (links != null) {
            for (uint i = 0; i < links.get_length (); i++) {
                var l = links.get_object_element (i);
                if (jstr (l, "rel").down ().contains ("bijlage") && jstr (l, "href") != "")
                    yield load_bijlagen (jstr (l, "href"), my);
            }
        }
        if (my != gen) return;
        show_raw (full ?? o_as_node (o));
    }

    Json.Node o_as_node (Json.Object o) {
        var n = new Json.Node (Json.NodeType.OBJECT);
        n.set_object (o);
        return n;
    }
}

public class MessagesPage : Page {
    public MessagesPage (Client c) { base (c, "Count", 40, 5, 200); }

    protected override string list_path () {
        return "/api/berichten?top=%d".printf ((int) spin.value);
    }

    protected override void row_info (Json.Object o, out string title, out string sub,
                                      out string trail, out bool bold) {
        title = jstr (o, "onderwerp");
        if (title == "") title = "(no subject)";
        sub = jstr (jobj (o, "afzender"), "naam");
        trail = fmt_date (jstr (o, "verzondenOp"));
        if (jstr (o, "heeftBijlagen") == "true") trail = "📎 " + trail;
        bold = jstr (o, "isGelezen") == "false";
    }

    protected override async void load_detail (Json.Object o) throws Error {
        uint64 my = gen;
        string id = jstr (o, "id");
        string self = jstr (o, "selfHref");
        if (self == "") self = jstr (jobj (jobj (o, "links"), "self"), "href");

        // full message through its selfHref
        Json.Node? raw = null;
        string err = "";
        if (self != "") {
            try {
                raw = yield client.get_raw (self);
            } catch (Error e) { err = e.message; }
        }
        // fallback: the combined message endpoint (slower: it pages through the inbox)
        Json.Node? att = null;
        if (raw == null) {
            try {
                att = yield client.get_json ("/api/berichten/" + id);
            } catch (Error e) { if (err == "") err = e.message; }
        }
        if (my != gen) return;

        Json.Object? m = null;
        if (raw != null && raw.get_node_type () == Json.NodeType.OBJECT) {
            m = raw.get_object ();
        } else if (att != null && att.get_node_type () == Json.NodeType.OBJECT) {
            var r = att.get_object ();
            m = jobj (r, "message") ?? r;
        }
        if (m == null) throw new IOError.FAILED ("Message not loaded: %s", err);

        string body = jstr (m, "inhoud");
        if (body == "") body = jstr (m, "body");
        if (body == "") body = jstr (m, "tekst");
        if (body == "") {
            string guess = longest_string (new Json.Node.alloc ().init_object (m));
            if (guess.length > 40) body = guess;
        }

        string subj = jstr (m, "onderwerp");
        if (subj == "") subj = jstr (o, "onderwerp");
        string from = jstr (jobj (m, "afzender"), "naam");
        if (from == "") from = jstr (jobj (o, "afzender"), "naam");
        string sent = jstr (m, "verzondenOp");
        if (sent == "") sent = jstr (o, "verzondenOp");

        var sb = new StringBuilder ();
        sb.append ("<span size='x-large' weight='bold'>" + esc (subj) + "</span>\n\n");
        sb.append (kv ("From", from));
        sb.append (kv ("To", names (m, "ontvangers", "weergavenaam", "naam")));
        sb.append (kv ("Sent", fmt_time (sent)));
        sb.append ("\n" + (body != "" ? esc (strip_html (body)) : "<i>(no message text found, see Raw JSON)</i>") + "\n");
        detail.label = sb.str;

        // attachments: the list lives at links.bijlagen.href of the message
        string bhref = jstr (jobj (jobj (m, "links"), "bijlagen"), "href");
        if (bhref == "" && jstr (m, "heeftBijlagen") == "true" && self != "")
            bhref = self + "/bijlagen";
        if (bhref != "")
            yield load_bijlagen (bhref, my);
        else if (att != null && att.get_node_type () == Json.NodeType.OBJECT)
            add_bijlagen (jarr (att.get_object (), "bijlagen"));
        if (my != gen) return;
        show_raw (raw ?? att);
    }
}

public class GradesPage : Page {
    public GradesPage (Client c) { base (c, "Count", 25, 5, 200); }

    protected override string list_path () {
        return "/api/cijfers?top=%d".printf ((int) spin.value);
    }

    protected override void row_info (Json.Object o, out string title, out string sub,
                                      out string trail, out bool bold) {
        var vak = jobj (o, "vak");
        title = jstr (vak, "omschrijving");
        if (title == "") title = jstr (vak, "code");
        if (title == "") title = "(subject)";
        string w = jstr (o, "weegfactor");
        sub = jstr (o, "omschrijving");
        if (w != "") sub += (sub != "" ? "  ·  " : "") + "weight " + w;
        string d = fmt_date (jstr (o, "ingevoerdOp"));
        if (d != "") sub += (sub != "" ? "  ·  " : "") + d;
        trail = jstr (o, "waarde");
        bold = false;
    }

    protected override async void load_detail (Json.Object o) throws Error {
        var vak = jobj (o, "vak");
        var sb = new StringBuilder ();
        sb.append ("<span size='x-large' weight='bold'>" + esc (jstr (vak, "omschrijving")) + "</span>\n\n");
        sb.append (kv ("Grade", jstr (o, "waarde")));
        sb.append (kv ("Item", jstr (o, "omschrijving")));
        sb.append (kv ("Weight", jstr (o, "weegfactor")));
        sb.append (kv ("Entered", fmt_time (jstr (o, "ingevoerdOp"))));
        detail.label = sb.str;
        var n = new Json.Node (Json.NodeType.OBJECT);
        n.set_object (o);
        show_raw (n);
    }
}

public class StudyGuidesPage : Page {
    public StudyGuidesPage (Client c) { base (c, "", 0, 0, 1); }

    protected override string list_path () { return "/api/studiewijzers"; }

    protected override void row_info (Json.Object o, out string title, out string sub,
                                      out string trail, out bool bold) {
        title = jstr (o, "titel");
        if (title == "") title = jstr (o, "naam");
        if (title == "") title = "(study guide)";
        string tot = jstr (o, "totEnMet");
        if (tot == "") tot = jstr (o, "tot");
        sub = fmt_date (jstr (o, "van")) + " – " + fmt_date (tot);
        var codes = jarr (o, "vakCodes");
        if (codes != null && codes.get_length () > 0) {
            var sb = new StringBuilder ();
            for (uint i = 0; i < codes.get_length (); i++) {
                if (i > 0) sb.append (", ");
                sb.append (codes.get_string_element (i));
            }
            sub += "  ·  " + sb.str;
        }
        trail = "";
        bold = false;
    }

    protected override async void load_detail (Json.Object o) throws Error {
        uint64 my = gen;
        string title = jstr (o, "titel");
        string self = jstr (o, "selfHref");
        if (self == "") self = link_href (o, "Self");

        detail.label = "<span size='x-large' weight='bold'>" + esc (title) + "</span>\n\n<i>Loading sections…</i>";

        Json.Node? node = null;
        if (self != "") {
            try {
                node = yield client.get_raw (self);
            } catch (Error e) { /* fall back below */ }
        }
        if (my != gen) return;
        if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
            yield fallback_detail (o, my, title);
            return;
        }

        var d = node.get_object ();
        var ond = jarr (d, "onderdelen");
        var head = new StringBuilder ();
        head.append ("<span size='x-large' weight='bold'>" + esc (title) + "</span>\n\n");
        head.append (kv ("Period", fmt_date (jstr (o, "van")) + " – " + fmt_date (jstr (o, "totEnMet"))));
        uint total = ond == null ? 0 : ond.get_length ();
        head.append (kv ("Sections", "%u".printf (total)));
        detail.label = head.str;
        show_raw (node);
        if (total == 0) {
            status.label = "This study guide has no sections";
            return;
        }

        for (uint i = 0; i < total; i++) {
            var x = ond.get_object_element (i);
            string t = jstr (x, "titel");
            if (t == "") t = jstr (x, "naam");
            if (t == "") t = "Section";
            bool hidden = jstr (x, "isZichtbaar") == "false";
            Label body;
            Box fbox = add_section ("%u.  %s%s".printf (i + 1, t, hidden ? "  (hidden)" : ""), out body);

            string desc = strip_html (jstr (x, "omschrijving"));
            string href = link_href (x, "Self");
            status.label = "Loading section %u of %u…".printf (i + 1, total);
            if (href != "") {
                try {
                    var on = yield client.get_raw (href);
                    if (my != gen) return;
                    if (on.get_node_type () == Json.NodeType.OBJECT) {
                        var od = on.get_object ();
                        string d2 = strip_html (jstr (od, "omschrijving"));
                        if (d2 != "") desc = d2;
                        fill_resources (fbox, jarr (od, "bronnen"));
                    }
                } catch (Error e) {
                    if (my != gen) return;
                    desc += (desc != "" ? "\n\n" : "") + "Could not load this section: " + e.message;
                }
            }
            if (desc != "") { body.label = desc; body.visible = true; }
        }
        status.label = "%u sections".printf (total);
    }

    // resources of one section: files become download buttons, web addresses open in the browser
    void fill_resources (Box target, Json.Array? bronnen) {
        if (bronnen == null) return;
        for (uint i = 0; i < bronnen.get_length (); i++) {
            var b = bronnen.get_object_element (i);
            string name = jstr (b, "naam");
            if (name == "") name = "file";
            string ctype = jstr (b, "contentType");
            string uri = jstr (b, "uri");
            string file_href = link_href (b, "Contents");
            if (file_href == "") file_href = link_href (b, "Content");
            if (file_href == "") file_href = link_href (b, "Download");

            bool looks_like_link = ctype.down ().contains ("uri") || ctype.down ().contains ("url")
                || ctype.down ().contains ("link");
            if (is_http (uri) && (file_href == "" || looks_like_link)) {
                add_link_to (target, name, uri);
            } else if (file_href != "") {
                add_file_to (target, name + size_label (jstr (b, "grootte")), file_href, name, ctype);
            } else if (uri != "") {
                add_file_to (target, name, uri, name, ctype);
            }
        }
    }

    // if the school API cannot be read directly, use the server's combined endpoint
    async void fallback_detail (Json.Object o, uint64 my, string title) throws Error {
        var node = yield client.get_json ("/api/studiewijzers/" + jstr (o, "id"));
        if (my != gen) return;
        var d = node.get_object ();
        detail.label = "<span size='x-large' weight='bold'>" + esc (title) + "</span>\n";
        var ond = jarr (d, "onderdelen");
        if (ond != null) {
            for (uint i = 0; i < ond.get_length (); i++) {
                var x = ond.get_object_element (i);
                Label body;
                Box fbox = add_section ("%u.  %s".printf (i + 1, jstr (x, "titel")), out body);
                string desc = strip_html (jstr (x, "omschrijving"));
                if (desc != "") { body.label = desc; body.visible = true; }
                var br = jarr (x, "bronnen");
                if (br == null) continue;
                for (uint j = 0; j < br.get_length (); j++) {
                    var b = br.get_object_element (j);
                    string dp = jstr (b, "downloadPath");
                    if (dp == "") continue;
                    string name = jstr (b, "naam");
                    add_file_to (fbox, name + size_label (jstr (b, "grootte")), dp, name, jstr (b, "contentType"));
                }
            }
        }
        show_raw (node);
    }
}

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

// ---------------------------------------------------------------- window

public class Window : ApplicationWindow {
    Client client = new Client ();
    Stack stack = new Stack ();
    Page[] pages = {};
    string cfg_path;

    public Window (Gtk.Application app) {
        Object (application: app, title: "Magister", default_width: 1100, default_height: 720);
        Intl.setlocale (LocaleCategory.TIME, "C");   // English day and month names
        apply_dark_orange_theme ();
        cfg_path = Path.build_filename (Environment.get_user_config_dir (), "magister-gtk", "config.ini");
        load_config ();

        pages = {
            new AppointmentsPage (client), new MessagesPage (client),
            new GradesPage (client), new StudyGuidesPage (client)
        };
        // 1. Create and add your image widget before the loop
    // For GTK4 (Recommended for files):
var dashboard_image = new Gtk.Image.from_resource ("/nl/magister/gtk/image.jpg");    
    // For GTK3 (Uncomment if using GTK3):
    // var dashboard_image = new Gtk.Image.from_file ("path/to/your/image.png");

    // Add it to the stack so it shows up in your navigation/switcher
    
        string[] ids = { "appointments", "messages", "grades", "studyguides" };
        string[] labels = { "Appointments", "Messages", "Grades", "Study guides" };
        //add image here
        for (int i = 0; i < pages.length; i++) stack.add_titled (pages[i], ids[i], labels[i]);

        var header = new HeaderBar ();
         // Enforce a small size constraint (e.g., 24x24 or 32x32 pixels)
    dashboard_image.set_pixel_size (32);
    dashboard_image.add_css_class ("app-logo");
    dashboard_image.margin_start = 6; // Add a little breathing room from the window edge
    
    // Pack it to the far left side
    header.pack_start (dashboard_image);
        header.title_widget = new StackSwitcher () { stack = stack };
        var settings = new Button.from_icon_name ("preferences-system-symbolic");
        settings.tooltip_text = "Settings";
        settings.clicked.connect (open_settings);
        header.pack_end (settings);
        set_titlebar (header);
        child = stack;

        stack.notify["visible-child"].connect (() => {
            var p = stack.visible_child as Page;
            if (p != null && client.key != "") p.ensure_loaded ();
        });

        if (client.key == "") {
            Idle.add (() => { open_settings (); return false; });
        } else {
            pages[0].ensure_loaded ();
        }
    }

    void load_config () {
        var kf = new KeyFile ();
        try {
            kf.load_from_file (cfg_path, KeyFileFlags.NONE);
            client.base_url = kf.get_string ("server", "url");
            client.key = kf.get_string ("server", "key");
        } catch (Error e) { /* first run */ }
        // environment (set by run.sh) wins over the saved config
        string? eu = Environment.get_variable ("MAGISTER_URL");
        string? ek = Environment.get_variable ("MAGISTER_API_KEY");
        if (eu != null && eu != "") client.base_url = eu;
        if (ek != null && ek != "") client.key = ek;
    }

    void save_config () {
        var kf = new KeyFile ();
        kf.set_string ("server", "url", client.base_url);
        kf.set_string ("server", "key", client.key);
        DirUtils.create_with_parents (Path.get_dirname (cfg_path), 0700);
        try {
            FileUtils.set_contents (cfg_path, kf.to_data ());
            FileUtils.chmod (cfg_path, 0600);
        } catch (Error e) { warning ("config: %s", e.message); }
    }

    void open_settings () {
        var w = new Gtk.Window () {
            title = "Settings", modal = true, transient_for = this, resizable = false
        };
        var grid = new Grid () {
            row_spacing = 10, column_spacing = 12,
            margin_top = 18, margin_bottom = 18, margin_start = 18, margin_end = 18
        };
        var url = new Entry () { text = client.base_url, hexpand = true, width_chars = 36 };
        var key = new PasswordEntry () { show_peek_icon = true };
        key.text = client.key;
        var hint = new Label ("Start the backend first:  MAGISTER_API_KEY=… ./Magister2 \"school\" <username> serve") {
            xalign = 0f, selectable = true
        };
        hint.add_css_class ("dim-label");
        hint.add_css_class ("caption");
        var save = new Button.with_label ("Save") { halign = Align.END };
        save.add_css_class ("suggested-action");
        save.clicked.connect (() => {
            client.base_url = url.text.strip ();
            client.key = key.text.strip ();
            save_config ();
            w.close ();
            foreach (var p in pages) p.invalidate ();
            (stack.visible_child as Page)?.ensure_loaded ();
        });

        grid.attach (new Label ("Server") { xalign = 1f }, 0, 0);
        grid.attach (url, 1, 0);
        grid.attach (new Label ("API key") { xalign = 1f }, 0, 1);
        grid.attach (key, 1, 1);
        grid.attach (hint, 0, 2, 2, 1);
        grid.attach (save, 0, 3, 2, 1);
        w.child = grid;
        w.present ();
    }
}

int main (string[] args) {
    var app = new Gtk.Application ("nl.magister.gtk", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => {
        var w = app.active_window ?? new Window (app);
        w.present ();
    });
    return app.run (args);
}