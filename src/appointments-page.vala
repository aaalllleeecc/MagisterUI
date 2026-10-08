using Gtk;

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

    protected override string day_key (Json.Object o) {
        string iso = jstr (o, "start");
        if (iso == "") return "";
        DateTime? dt = new DateTime.from_iso8601 (iso, null);
        if (dt == null) return iso.length >= 10 ? iso.substring (0, 10) : iso;
        return dt.to_local ().format ("%Y-%m-%d");
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
