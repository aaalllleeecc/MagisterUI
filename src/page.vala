using Gtk;

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

    // Pages can return a grouping key (e.g. the date) to get an orange divider
    // line between groups. Empty string = no dividers.
    protected virtual string day_key (Json.Object o) { return ""; }

    void update_header (ListBoxRow row, ListBoxRow? before) {
        row.set_header (null);
        if (before == null || items == null) return;

        int i = row.get_index ();
        int j = before.get_index ();
        uint n = items.get_length ();
        if (i < 0 || j < 0 || i >= (int) n || j >= (int) n) return;

        string a = day_key (items.get_object_element (i));
        string b = day_key (items.get_object_element (j));
        if (a == "" || a == b) return;

        var line = new Box (Orientation.HORIZONTAL, 0);
        line.add_css_class ("day-divider");
        row.set_header (line);
    }

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
        list.set_header_func ((row, before) => { update_header (row, before); });
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
