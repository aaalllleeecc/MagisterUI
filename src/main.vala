using Gtk;

int main (string[] args) {
    var app = new Gtk.Application ("nl.magister.gtk", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => {
        var w = app.active_window ?? new Window (app);
        w.present ();
    });
    return app.run (args);
}