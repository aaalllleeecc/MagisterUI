using Gtk;

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
            new GradesPage (client), new StudyGuidesPage (client),
            new AssignmentsPage(client)
        };
        // 1. Create and add your image widget before the loop
    // For GTK4 (Recommended for files):
var dashboard_image = new Gtk.Image.from_resource ("/nl/magister/gtk/image.jpg");    
    // For GTK3 (Uncomment if using GTK3):
    // var dashboard_image = new Gtk.Image.from_file ("path/to/your/image.png");

    // Add it to the stack so it shows up in your navigation/switcher
    
        string[] ids = { "appointments", "messages", "grades", "studyguides", "assignments" };
        string[] labels = { "Appointments", "Messages", "Grades", "Study guides", "Assignments" };
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
