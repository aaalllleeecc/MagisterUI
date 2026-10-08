// Shared JSON / formatting helpers

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

    var t = n.get_value_type ();
    if (t == typeof (string)) return n.get_string () ?? "";
    if (t == typeof (int64))  return n.get_int ().to_string ();
    if (t == typeof (double)) return n.get_double ().to_string ();
    if (t == typeof (bool))   return n.get_boolean ().to_string ();
    return "";
}
int64 jint (Json.Object? o, string key) {
    if (o == null) return 0;
    string k = key;
    if (!o.has_member (k)) {
        k = key.substring (0, 1).up () + key.substring (1);
        if (!o.has_member (k)) return 0;
    }
    var n = o.get_member (k);
    if (n.get_node_type () != Json.NodeType.VALUE) return 0;

    // number -> int, string -> parse it
    if (n.get_value_type () == typeof (string))
        return int64.parse (n.get_string () ?? "0");
    return n.get_int ();
}
string normalize_person_type (string raw) {
    switch (raw.down ().strip ()) {
        case "":
        case "leerling":
            return "leerling";
        case "docent":
        case "medewerker":
            return "medewerker";   // verify with a real capture
        default:
            return raw.down ().strip ();
    }
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
