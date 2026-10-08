using Gtk;

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
