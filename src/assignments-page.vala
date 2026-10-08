using Gtk;

// Assignments (Opdrachten): list from /api/opdrachten, detail from /api/opdrachten/{id}

public class AssignmentsPage : Page {
    public AssignmentsPage (Client c) { base (c, "", 0, 0, 1); }

    protected override string list_path () { return "/api/opdrachten"; }

    // -------- small helpers

    static bool flag (Json.Object? o, string key) {
        return jstr (o, key) == "true";
    }

    // "vak" is a plain string in the model, but accept an object with "omschrijving" too
    static string subject_of (Json.Object o) {
        string v = jstr (o, "vak");
        if (v == "") v = jstr (jobj (o, "vak"), "omschrijving");
        return v;
    }

    static bool is_overdue (Json.Object o) {
        if (jstr (o, "ingeleverdOp") != "") return false;
        string iso = jstr (o, "inleverenVoor");
        if (iso == "") return false;
        DateTime? due = new DateTime.from_iso8601 (iso, null);
        return due != null && due.compare (new DateTime.now_utc ()) < 0;
    }

    // -------- list

    protected override void row_info (Json.Object o, out string title, out string sub,
                                      out string trail, out bool bold) {
        title = jstr (o, "titel");
        if (title == "") title = "(assignment)";

        string due = fmt_time (jstr (o, "inleverenVoor"));
        sub = subject_of (o);
        if (due != "") sub += (sub != "" ? "  ·  " : "") + "due " + due;

        bool submitted = jstr (o, "ingeleverdOp") != "";
        trail = submitted ? "✔" : (is_overdue (o) ? "⚠" : "");
        // bold = still open and not handed in yet
        bold = !submitted && !flag (o, "afgesloten");
    }

    // -------- detail

    protected override async void load_detail (Json.Object o) throws Error {
        uint64 my = gen;
        Json.Object d = o;
        Json.Node? full = null;
        try {
            full = yield client.get_json ("/api/opdrachten/" + jstr (o, "id"));
            if (full.get_node_type () == Json.NodeType.OBJECT) d = full.get_object ();
        } catch (Error e) { /* fall back to the list item */ }
        if (my != gen) return;

        string title = jstr (d, "titel");
        if (title == "") title = jstr (o, "titel");

        string submitted = jstr (d, "ingeleverdOp");
        string status_text;
        if (submitted != "")
            status_text = "Handed in on " + fmt_time (submitted);
        else if (is_overdue (d))
            status_text = "Overdue, not handed in";
        else
            status_text = "Not handed in yet";

        var flags = new StringBuilder ();
        if (flag (d, "opnieuwInleveren")) flags.append ("resubmit required");
        if (flag (d, "afgesloten")) {
            if (flags.len > 0) flags.append (", ");
            flags.append ("closed");
        }
        if (flag (d, "magInleveren")) {
            if (flags.len > 0) flags.append (", ");
            flags.append ("you can hand in");
        }

        var sb = new StringBuilder ();
        sb.append ("<span size='x-large' weight='bold'>" + esc (title) + "</span>\n\n");
        sb.append (kv ("Subject", subject_of (d)));
        sb.append (kv ("Teacher", names (d, "docenten", "naam", "weergavenaam")));
        sb.append (kv ("Due", fmt_time (jstr (d, "inleverenVoor"))));
        sb.append (kv ("Status", status_text));
        sb.append (kv ("Version", jstr (d, "laatsteOpdrachtVersienummer")));
        sb.append (kv ("Flags", flags.str));

        string graded_on = jstr (d, "beoordeeldOp");
        if (graded_on != "") sb.append (kv ("Graded on", fmt_time (graded_on)));
        string grade = strip_html (jstr (d, "beoordeling"));
        if (grade != "") sb.append ("\n<b>Assessment</b>\n" + esc (grade) + "\n");

        string desc = strip_html (jstr (d, "omschrijving"));
        if (desc != "") sb.append ("\n<b>Description</b>\n" + esc (desc) + "\n");
        detail.label = sb.str;

        add_attachments (jarr (d, "bijlagen"));

        if (my != gen) return;
        show_raw (full ?? as_node (o));
    }

    // attachments of an assignment: download buttons
    void add_attachments (Json.Array? arr) {
        if (arr == null) return;
        for (uint i = 0; i < arr.get_length (); i++) {
            if (arr.get_element (i).get_node_type () != Json.NodeType.OBJECT) continue;
            var a = arr.get_object_element (i);

            string href = jstr (jobj (jobj (a, "links"), "download"), "href");
            if (href == "") href = link_href (a, "Contents");
            if (href == "") href = link_href (a, "Content");
            if (href == "") href = link_href (a, "Download");
            if (href == "") href = link_href (a, "Self");   // metadata; download() follows it
            if (href == "") continue;

            string name = jstr (a, "naam");
            if (name == "") name = "attachment-" + jstr (a, "id");
            add_file (name + size_label (jstr (a, "grootte")), href, name, jstr (a, "contentType"));
        }
    }

    Json.Node as_node (Json.Object o) {
        var n = new Json.Node (Json.NodeType.OBJECT);
        n.set_object (o);
        return n;
    }
}