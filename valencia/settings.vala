/* Copyright 2009-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Gee; 
using Valencia;

class ProjectSettingsDialog : Object {
    Gtk.Dialog dialog;
    Gtk.Entry build_entry;
    Gtk.Entry clean_entry;
    Gtk.Entry blacklist_entry;

    string build_command;
    string clean_command;
    string pkg_blacklist;

    public signal void settings_changed(string new_build_command, string new_clean_command,
        string pkg_blacklist);

    public ProjectSettingsDialog(Gtk.Window parent_win) {
        // Window creation
        Gtk.Label build_command_label = new Gtk.Label("Build command:");
        build_entry = new Gtk.Entry();
        build_entry.activate.connect(on_entry_activated);
        build_entry.hexpand = true;
        
        Gtk.Alignment align_build_label = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        align_build_label.add(build_command_label);

        Gtk.Label clean_command_label = new Gtk.Label("Clean command:");
        clean_entry = new Gtk.Entry();
        clean_entry.activate.connect(on_entry_activated);
        clean_entry.hexpand = true;
        
        Gtk.Alignment align_clean_label = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        align_clean_label.add(clean_command_label);
        
        Gtk.Label blacklist_label = new Gtk.Label("VAPI blacklist:");
        blacklist_entry = new Gtk.Entry();
        blacklist_entry.activate.connect(on_entry_activated);
        blacklist_entry.tooltip_text =
            "Semicolon-delimited list of package names, i.e. \"gtk+-2.0;gee-1.0\"";
        blacklist_entry.hexpand = true;
        
        Gtk.Alignment align_blacklist_label = new Gtk.Alignment(0.0f, 0.5f, 0.0f, 0.0f);
        align_blacklist_label.add(blacklist_label);
        
        Gtk.Grid grid = new Gtk.Grid();
        grid.set_column_spacing(12);
        grid.set_row_spacing(6);
        
        grid.attach(align_build_label, 0, 0, 1, 1);
        grid.attach(align_clean_label, 0, 1, 1, 1);
        grid.attach(align_blacklist_label, 0, 2, 1, 1);
        grid.attach(build_entry, 1, 0, 1, 1);
        grid.attach(clean_entry, 1, 1, 1, 1);
        grid.attach(blacklist_entry, 1, 2, 1, 1);
         
        Gtk.Alignment alignment_box = new Gtk.Alignment(0.5f, 0.5f, 1.0f, 1.0f);
        alignment_box.set_padding(5, 6, 6, 5);
        alignment_box.add(grid);

        dialog = new Gtk.Dialog.with_buttons("Settings", parent_win, Gtk.DialogFlags.MODAL |
                                             Gtk.DialogFlags.DESTROY_WITH_PARENT, 
                                             Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, 
                                             Gtk.Stock.OK, Gtk.ResponseType.OK, null);
        dialog.set_default_response(Gtk.ResponseType.OK);
        dialog.set_default_size(350, 10);
        dialog.delete_event.connect(dialog.hide_on_delete);

        Gtk.Box content_area = (Gtk.Box) dialog.get_content_area();
        content_area.pack_start(alignment_box, false, false, 0);
        // Make all children visible by default
        content_area.show_all();
    }

    void on_entry_activated() {
        dialog.response(Gtk.ResponseType.OK);
    }

    void load_settings(string active_filename) {
        Program program = Program.find_containing(active_filename);
        
        build_command = program.config_file.get_build_command();
        clean_command = program.config_file.get_clean_command();
        pkg_blacklist = program.config_file.get_pkg_blacklist();
    }

    public void show(string active_filename) {
        // On first-time startup, look for a .valencia file that may have a stored build command
        load_settings(active_filename);

        build_entry.set_text(build_command);
        clean_entry.set_text(clean_command);
        blacklist_entry.set_text(pkg_blacklist);

        dialog.set_focus(build_entry);
        int result = dialog.run();
        switch (result) {
            case Gtk.ResponseType.OK:
                save_and_close();
                break;
            default:
                hide();
                break;
        }
    }

    void hide() {
        dialog.hide();
    }

    void save_and_close() {
        string new_build_command = build_entry.get_text();
        string new_clean_command = clean_entry.get_text();
        string new_pkg_blacklist = blacklist_entry.get_text();

        bool changed = false;
        if (new_build_command != build_command && new_build_command != "") {
            build_command = new_build_command;
            changed = true;
        }

        if (new_clean_command != clean_command && new_clean_command != "") {
            clean_command = new_clean_command;
            changed = true;
        }
       
        if (new_pkg_blacklist != pkg_blacklist && new_pkg_blacklist != "") {
            pkg_blacklist = new_pkg_blacklist;
            changed = true;
        }
       
        if (changed)
            settings_changed(build_command, clean_command, pkg_blacklist);

        hide();
    }

}

