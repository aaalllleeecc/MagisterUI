using Gtk;

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
