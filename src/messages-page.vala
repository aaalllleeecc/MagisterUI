using Gtk;

public class MessagesPage : Page {
 public MessagesPage (Client c) {
    base (c, "Count", 40, 5, 200);

    var compose = new Button.with_label ("Compose message");
    compose.add_css_class ("suggested-action");
    
    // Put the button at the top of the page.
    var controls = get_first_child () as Box;
    if (controls != null)
        controls.append (compose);

    compose.clicked.connect (() => {
        open_compose ();
    });
}
void open_compose () {
    var dialog = new Gtk.Window () {
        title = "New message",
        modal = true,
        transient_for = get_root () as Gtk.Window,
        default_width = 600,
        default_height = 500,
        resizable = true
    };

    var outer = new Box (Orientation.VERTICAL, 12) {
        margin_top = 18,
        margin_bottom = 18,
        margin_start = 18,
        margin_end = 18
    };

    // Recipient search
    var recipient_box = new Box (Orientation.HORIZONTAL, 8);

    var recipient_search = new Entry () {
        placeholder_text = "Search for a person…",
        hexpand = true
    };

    var search_button = new Button.with_label ("Search");

    recipient_box.append (recipient_search);
    recipient_box.append (search_button);

    var people = new ListBox () {
        vexpand = true,
        selection_mode = SelectionMode.SINGLE
    };

    var people_scroll = new ScrolledWindow () {
        child = people,
        min_content_height = 140,
        vexpand = true
    };

    var selected_label = new Label ("No recipient selected") {
        xalign = 0f
    };
    selected_label.add_css_class ("dim-label");

    int selected_id = -1;
    string selected_type = "leerling";

    search_button.clicked.connect (() => {
        search_people.begin (recipient_search.text, people, selected_label);
    });

    // clicking a row selects it (the row's own "activate" only fires on Enter/Space)
    people.row_selected.connect ((row) => {
        var person = row as PersonRow;
        if (person == null) {
            selected_id = -1;
            return;
        }
        selected_id = person.person_id;
        selected_type = normalize_person_type (person.person_type);   // <- changed
        selected_label.label =
            "Recipient: %s (%d)".printf (person.person_name, person.person_id);
    });

    recipient_search.activate.connect (() => {
        search_button.clicked ();
    });

    // Subject
    var subject = new Entry () {
        placeholder_text = "Subject"
    };

    // Body
    var body = new TextView () {
        wrap_mode = WrapMode.WORD_CHAR,
        vexpand = true
    };

    var body_scroll = new ScrolledWindow () {
        child = body,
        vexpand = true
    };

    // Buttons
    var buttons = new Box (Orientation.HORIZONTAL, 8) {
        halign = Align.END
    };

    var cancel = new Button.with_label ("Cancel");
    var send = new Button.with_label ("Send");
    send.add_css_class ("suggested-action");

    buttons.append (cancel);
    buttons.append (send);

    cancel.clicked.connect (() => {
        dialog.close ();
    });

    send.clicked.connect (() => {
        if (selected_id < 0) {
            selected_label.label = "Please select a recipient.";
            return;
        }

        if (subject.text.strip () == "") {
            selected_label.label = "Please enter a subject.";
            return;
        }

        var buffer = body.buffer;
        string text = buffer.text.strip ();

        if (text == "") {
            selected_label.label = "Please enter a message.";
            return;
        }

        send_message.begin (
            dialog,
            selected_id,
            selected_type,
            subject.text,
            text,
            send,
            selected_label
        );
    });

    outer.append (recipient_box);
    outer.append (people_scroll);
    outer.append (selected_label);
    outer.append (subject);
    outer.append (body_scroll);
    outer.append (buttons);

    dialog.child = outer;
    dialog.present ();
}
class PersonRow : ListBoxRow {
    public int person_id;
    public string person_name = "";
    public string person_type = "leerling";
}

async void search_people (
    string query,
    ListBox people,
    Label selected_label
) {
    Widget? child;

    while ((child = people.get_first_child ()) != null)
        people.remove (child);

    if (query.strip () == "") {
        selected_label.label = "Enter a name to search.";
        return;
    }

    selected_label.label = "Searching…";

    try {
        var node = yield client.search_people (query);

        var array = items_of_node (node);

        if (array == null || array.get_length () == 0) {
            selected_label.label = "No people found.";
            return;
        }

        for (uint i = 0; i < array.get_length (); i++) {
            var person = array.get_object_element (i);

            int id = (int) jint (person, "id");
            string first = jstr (person, "roepnaam");
            string middle = jstr (person, "tussenvoegsel");
            string last = jstr (person, "achternaam");

            string name = first;

            if (middle != "")
                name += " " + middle;

            if (last != "")
                name += " " + last;

            if (name == "")
                name = "(unknown person)";

            string klas = jstr (person, "klas");
            string type = jstr (person, "type");

            string subtitle = "";
            if (klas != "")
                subtitle += klas;
            if (type != "")
                subtitle += (subtitle != "" ? " · " : "") + type;

            var row = new PersonRow ();

            var box = new Box (Orientation.VERTICAL, 2) {
                margin_top = 7,
                margin_bottom = 7,
                margin_start = 10,
                margin_end = 10
            };

            var name_label = new Label (esc (name)) {
                xalign = 0f,
                use_markup = true
            };

            box.append (name_label);

            if (subtitle != "") {
                var sub = new Label (esc (subtitle)) {
                    xalign = 0f,
                    use_markup = true
                };
                sub.add_css_class ("dim-label");
                box.append (sub);
            }

            row.person_id = id;
            row.person_name = name;
            row.person_type = type == "" ? "leerling" : type;

            row.child = box;
            people.append (row);
        }

        selected_label.label =
            "%u people found — select one.".printf (array.get_length ());

    } catch (Error e) {
        selected_label.label = "Search failed: " + e.message;
    }
}
async void send_message (
    Gtk.Window dialog,
    int recipient_id,
    string recipient_type,
    string subject,
    string content,
    Button send,
    Label status
) {
    send.sensitive = false;
    status.label = "Sending…";

    try {
        yield client.send_message (
            recipient_id,
            recipient_type,
            subject,
            content
        );

        status.label = "Message sent.";
        send.sensitive = true;

        // Refresh the inbox after sending.
        refresh.begin ();

        dialog.close ();

    } catch (Error e) {
        send.sensitive = true;
        status.label = "Sending failed: " + e.message;
    }
}
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
