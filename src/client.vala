// HTTP client for the local Magister backend

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
    public async Json.Node post_json (string path, Json.Object body) throws Error {
    string b = base_url;
    while (b.has_suffix ("/"))
        b = b.substring (0, b.length - 1);

    var msg = new Soup.Message ("POST", b + path);
    if (msg == null)
        throw new IOError.FAILED ("Invalid server URL");

    msg.request_headers.append ("Authorization", "Bearer " + key);
    msg.request_headers.append ("Content-Type", "application/json");

    var generator = new Json.Generator ();
    var node = new Json.Node (Json.NodeType.OBJECT);
    node.set_object (body);
    generator.set_root (node);

    string json = generator.to_data (null);

    msg.set_request_body_from_bytes (
        "application/json",
        new Bytes (json.data)
    );

    var bytes = yield session.send_and_read_async (
        msg, Priority.DEFAULT, null
    );

    if (msg.status_code < 200 || msg.status_code >= 300) {
        var data = bytes.get_data ();
        string body_text = "";
        if (data.length > 0)
            body_text = (string) data;

        throw new IOError.FAILED (
            "HTTP %u: %s",
            msg.status_code,
            body_text
        );
    }

    if (bytes.get_size () == 0)
        return new Json.Node (Json.NodeType.NULL);

    var p = new Json.Parser ();
    var data = bytes.get_data ();
    p.load_from_data ((string) data, data.length);
    return p.get_root ();
}
public async Json.Node search_people (string query) throws Error {
    return yield get_json (
        "/api/personen?q=" + Uri.escape_string (query, null, true)
    );
}
public async Json.Node send_message (
    int recipient_id,
    string recipient_type,
    string subject,
    string content
) throws Error {
    
    var recipient = new Json.Object ();
    recipient.set_int_member ("id", recipient_id);
    recipient.set_string_member ("type", "persoon");
    recipient.set_boolean_member ("aanHuidigeSelectie", false);
    recipient.set_string_member ("persoonType", recipient_type);

    var recipients = new Json.Array ();
    recipients.add_object_element (recipient);

    var cc = new Json.Array ();
    var bcc = new Json.Array ();
    var attachments = new Json.Array ();

    var body = new Json.Object ();
    body.set_array_member ("ontvangers", recipients);
    body.set_array_member ("kopieOntvangers", cc);
    body.set_array_member ("blindeKopieOntvangers", bcc);
    body.set_boolean_member ("heeftPrioriteit", false);
    body.set_string_member (
        "inhoud",
        "<p>" + Markup.escape_text (content).replace ("\n", "<br>") + "</p>"
    );
    body.set_string_member ("onderwerp", subject);
    body.set_string_member ("verzendOptie", "standaard");
    body.set_array_member ("bijlagen", attachments);
    var logNode = new Json.Node(Json.NodeType.OBJECT);
    logNode.set_object(body);
    var generator = new Json.Generator();
    generator.set_root(logNode);
    generator.pretty = true;
    string logString = generator.to_data(null);
    message("\n%s", logString);
    return yield post_json ("/api/berichten", body);
}
}
