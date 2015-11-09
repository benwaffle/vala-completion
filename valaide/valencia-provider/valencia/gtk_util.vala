/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Gee;

////////////////////////////////////////////////////////////
//                    Helper functions                    //
////////////////////////////////////////////////////////////

Gtk.TextIter get_insert_iter(Gtk.TextBuffer buffer) {
    Gtk.TextIter iter;
    buffer.get_iter_at_mark(out iter, buffer.get_insert());
    return iter;
}

void get_line_start_end(Gtk.TextIter iter, out Gtk.TextIter start, out Gtk.TextIter end) {
    start = iter;
    start.set_line_offset(0);
    end = iter;
    end.forward_line();
}

void append_with_tag(Gtk.TextBuffer buffer, string text, Gtk.TextTag? tag) {
    Gtk.TextIter end;
    buffer.get_end_iter(out end);
    if (tag != null)
        buffer.insert_with_tags(end, text, -1, tag);
    else
        buffer.insert(end, text, -1);
}

void append(Gtk.TextBuffer buffer, string text) {
    append_with_tag(buffer, text, null);
}

Gtk.TextIter iter_at_line_offset(Gtk.TextBuffer buffer, int line, int offset) {
    // We must be careful: TextBuffer.get_iter_at_line_offset() will crash if we give it an
    // offset greater than the length of the line.
    Gtk.TextIter iter;
    buffer.get_iter_at_line(out iter, line);
    int len = iter.get_chars_in_line() - 1;     // subtract 1 for \n
    if (len < 0)    // no \n was present, e.g. in an empty file
        len = 0;
    int end = int.min(len, offset);
    Gtk.TextIter ret;
    buffer.get_iter_at_line_offset(out ret, line, end);
    return ret;
}

unowned string buffer_contents(Gtk.TextBuffer buffer) {
    Gtk.TextIter start;
    Gtk.TextIter end;
    buffer.get_bounds(out start, out end);
    return buffer.get_text(start, end, true);
}

Gtk.MenuItem get_menu_item(Gtk.UIManager manager, string path) {
    Gtk.MenuItem item = (Gtk.MenuItem) manager.get_widget(path);
    assert(item != null);
    return item;
}

public void show_error_dialog(string message) {
    Gtk.MessageDialog err_dialog = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, 
                                                Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, 
                                                message, null);
    err_dialog.set_title("Error");
    err_dialog.run(); 
    err_dialog.destroy(); 
}

string get_full_line_from_text_iter(Gtk.TextIter iter) {
    // Move the iterator back to the beginning of its line
    iter.backward_chars(iter.get_line_offset());
    // Get an iterator at the end of the line
    Gtk.TextIter end = iter;
    end.forward_line();
    
    return iter.get_text(end);
}

void get_coords_at_buffer_offset(Gedit.Window window, int offset, bool above, bool beside,
                                 out int x, out int y) {
    Gedit.Document buffer = window.get_active_document();
    Gtk.TextIter method_iter;
    buffer.get_iter_at_offset(out method_iter, offset);
    
    Gedit.View active_view = window.get_active_view();
    Gdk.Rectangle rect;
    active_view.get_iter_location(method_iter, out rect);
    int win_x, win_y;
    active_view.buffer_to_window_coords(Gtk.TextWindowType.WIDGET, rect.x, rect.y, 
                                        out win_x, out win_y);
    int widget_x = active_view.allocation.x;
    int widget_y = active_view.allocation.y; 
    int orig_x, orig_y;
    window.window.get_origin(out orig_x, out orig_y);

    x = win_x + widget_x + orig_x;
    y = win_y + widget_y + orig_y;
    x += beside ? rect.height : 0; 
    y -= above ? rect.height : 0;
}

////////////////////////////////////////////////////////////
//                        Classes                         //
////////////////////////////////////////////////////////////

class Tooltip {
    weak Gedit.Window parent;
    Gtk.Window window;
    Gtk.Label tip_text;
    Gtk.TextMark method_mark;
    string method_name;
    bool visible;

    public Tooltip(Gedit.Window parent_win) {
        parent = parent_win;
        visible = false;
        tip_text = new Gtk.Label("");
        window = new Gtk.Window(Gtk.WindowType.POPUP);
        
        window.add(tip_text);
        window.set_default_size(1, 1);
        window.set_transient_for(parent);
        window.set_destroy_with_parent(true);
        
        Gdk.Color background;
        Gdk.Color.parse("#FFFF99", out background);
        window.modify_bg(Gtk.StateType.NORMAL, background);
    }

    public void show(string qualified_method_name, string prototype, int method_pos) {
        method_name = qualified_method_name;
        visible = true;

        Gedit.Document document = parent.get_active_document();
        Gtk.TextIter method_iter;
        document.get_iter_at_offset(out method_iter, method_pos);
        method_mark = document.create_mark(null, method_iter, true);
        tip_text.set_text(prototype);

        int x, y;
        get_coords_at_buffer_offset(parent, method_pos, true, false, out x, out y);
        window.move(x, y);
        window.resize(1, 1);
        window.show_all();
    }

    public void hide() {
        if (!visible)
            return;

        assert(!method_mark.get_deleted());
        Gtk.TextBuffer doc = method_mark.get_buffer();
        doc.delete_mark(method_mark);
        
        visible = false;
        window.hide_all();
    }
    
    public bool is_visible() {
        return visible;
    }
    
    public string get_method_line() {
        assert(!method_mark.get_deleted());
        Gtk.TextBuffer doc = method_mark.get_buffer();
        Gtk.TextIter iter;
        doc.get_iter_at_mark(out iter, method_mark);
        return get_full_line_from_text_iter(iter);
    }

    public Gtk.TextIter get_iter_at_method() {
        assert(!method_mark.get_deleted());
        Gtk.TextBuffer doc = method_mark.get_buffer();
        Gtk.TextIter iter;
        doc.get_iter_at_mark(out iter, method_mark);
        return iter;
    }
    
    public string get_method_name() {
        return method_name;
    }
}

class ProgressBarDialog : Gtk.Window {
    Gtk.ProgressBar bar;

    public ProgressBarDialog(Gtk.Window parent_win, string text) {
        bar = new Gtk.ProgressBar();
        Gtk.VBox vbox = new Gtk.VBox(true, 0);
        Gtk.HBox hbox = new Gtk.HBox(true, 0);

        bar.set_text(text);
        bar.set_size_request(226, 25);
        set_size_request(250, 49);

        vbox.pack_start(bar, true, false, 0);
        hbox.pack_start(vbox, true, false, 0);   
        add(hbox);
        set_title(text);

        set_resizable(false);
        set_transient_for(parent_win);
        set_position(Gtk.WindowPosition.CENTER_ON_PARENT);
        set_modal(true);
        show_all();
    }
    
    public void set_percentage(double percent) {
        bar.set_fraction(percent);
    }
    
    public void close() {
        hide();
    }
}

class SignalConnection : Object {
    public class SignalIDPair {
        public weak Object object;
        public ulong id;
        
        public SignalIDPair(Object object, ulong id) {
            this.object = object;
            this.id = id;
        }
    }

    public weak Object base_instance;
    ArrayList<SignalIDPair> instance_signal_id_pair;

    public SignalConnection(Object base_instance) {
        this.base_instance = base_instance;
        instance_signal_id_pair = new ArrayList<SignalIDPair>();
    }

    ~SignalConnection() {
        foreach (SignalIDPair pair in instance_signal_id_pair) {
            if (SignalHandler.is_connected(pair.object, pair.id))
                SignalHandler.disconnect(pair.object, pair.id);
        }
    }

    public void add_signal(Object instance, string signal_name, Callback cb, void *data,
                           bool after = false) {
        ulong id;
        if (after)
            id = Signal.connect_after(instance, signal_name, cb, data);
        else id = Signal.connect(instance, signal_name, cb, data);
        instance_signal_id_pair.add(new SignalIDPair(instance, id));
    }
}

class ListViewString : Object {
    Gtk.ListStore list;
    Gtk.TreeView treeview;
    Gtk.TreeViewColumn column_view;
    public Gtk.ScrolledWindow scrolled_window;
    
    public signal void row_activated();
    public signal void received_focus(Gtk.TreePath? path);

    public ListViewString(Gtk.TreeViewColumnSizing sizing, int fixed_width) {
        list = new Gtk.ListStore(1, GLib.Type.from_name("gchararray"));

        Gtk.CellRendererText renderer = new Gtk.CellRendererText();
        if (sizing == Gtk.TreeViewColumnSizing.FIXED)
            renderer.ellipsize = Pango.EllipsizeMode.END;
        column_view = new Gtk.TreeViewColumn();
        column_view.pack_start(renderer, true); 
        column_view.set_sizing(sizing);
        column_view.set_fixed_width(fixed_width);
        column_view.set_attributes(renderer, "text", 0, null);
        treeview = new Gtk.TreeView.with_model(list);
        treeview.append_column(column_view);
        treeview.headers_visible = false;
        treeview.focus_in_event.connect(on_received_focus);

        scrolled_window = new Gtk.ScrolledWindow(null, null); 
        scrolled_window.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled_window.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
        scrolled_window.add(treeview);
        
        Signal.connect(treeview, "row-activated", (Callback) row_activated_callback, this);
    }
    
    bool on_received_focus() {
        Gtk.TreePath? path = get_path_at_cursor();
        received_focus(path);
        return false;
    }
    
    static void row_activated_callback(Gtk.TreeView view, Gtk.TreePath path, 
                                       Gtk.TreeViewColumn column, ListViewString list) {
        list.row_activated();
    }
    
    public void clear() {
        list.clear();
    }
    
    public void append(string item) {
        Gtk.TreeIter iterator;
        list.append(out iterator);
        list.set(iterator, 0, item, -1);
    }
    
    public int size() {
        return list.iter_n_children(null);
    }
    
    public void set_vscrollbar_policy(Gtk.PolicyType policy) {
        scrolled_window.vscrollbar_policy = policy;
    }

    /////////////////////////////////
    // Treeview selection movement //
    /////////////////////////////////

    void select(Gtk.TreePath path, bool scroll = true) {
        treeview.set_cursor(path, null, false);
        if (scroll)
            treeview.scroll_to_cell(path, null, false, 0.0f, 0.0f);
    }
    
    void scroll_to_and_select_cell(double adjustment_value, int y) {
        scrolled_window.vadjustment.set_value(adjustment_value);        
        
        Gtk.TreePath path;
        int cell_x, cell_y;
        treeview.get_path_at_pos(0, y, out path, null, out cell_x, out cell_y);
        select(path, false);
    }
    
    Gtk.TreePath? get_path_at_cursor() {
        Gtk.TreePath path;
        Gtk.TreeViewColumn column;
        treeview.get_cursor(out path, out column);
        return path;
    }
    
    public Gtk.TreePath select_first_cell() {
        treeview.get_vadjustment().set_value(0);
        Gtk.TreePath start = new Gtk.TreePath.first();
        select(start);
        return start;
    }

    public void select_last_cell() {
        // The list index is 0-based, the last element is 'size - 1'
        int size = list.iter_n_children(null) - 1;
        select(new Gtk.TreePath.from_string(size.to_string()));
    }

    public void select_previous() {
        Gtk.TreePath path = get_path_at_cursor();
        
        if (path != null) {
            if (path.prev())
                select(path);
            else select_last_cell();
        }
    }

    public void select_next() {
        Gtk.TreePath path = get_path_at_cursor();
        
        if (path != null) {
            Gtk.TreeIter iter;
            path.next();

            // Make sure the next element iterator is valid
            if (list.get_iter(out iter, path))
                select(path);
            else select_first_cell();
        }
    }

    public void page_up() {
        // Save the current y position of the selection
        Gtk.TreePath cursor_path = get_path_at_cursor();
        Gdk.Rectangle rect;
        treeview.get_cell_area(cursor_path, null, out rect);
        
        // Don't wrap page_up
        if (!cursor_path.prev()) {
            return;
        }

        double adjust_value = scrolled_window.vadjustment.get_value();
        double page_size = scrolled_window.vadjustment.get_page_size();
        // If the current page is the top page, just select the top cell
        if (adjust_value == scrolled_window.vadjustment.lower) {
            select_first_cell();
            return;
        }

        // it is 'y + 1' because only 'y' would be the element before the one we want
        scroll_to_and_select_cell(adjust_value - (page_size - rect.height), rect.y + 1);
    }

    public void page_down() {
        // Save the current y position of the selection
        Gtk.TreePath cursor_path = get_path_at_cursor();
        Gdk.Rectangle rect;
        treeview.get_cell_area(cursor_path, null, out rect);
        
        // Don't wrap page_down
        cursor_path.next();
        Gtk.TreeIter iter;
        if (!list.get_iter(out iter, cursor_path)) {
            return;
        }

        double adjust_value = scrolled_window.vadjustment.get_value();
        double page_size = scrolled_window.vadjustment.get_page_size();
        // If the current page is the bottom page, just select the last cell
        if (adjust_value >= scrolled_window.vadjustment.upper - page_size) {
            select_last_cell();
            return;
        }

        scroll_to_and_select_cell(adjust_value + (page_size - rect.height), rect.y + 1);
    }

    string? get_item_at_path(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (!list.get_iter(out iter, path))
            return null;

        GLib.Value v;
        list.get_value(iter, 0, out v);

        return v.get_string().substring(0);
    }

    public string get_selected_item() {
        Gtk.TreePath path;
        Gtk.TreeViewColumn column;
        treeview.get_cursor(out path, out column);
        
        return get_item_at_path(path);
    }

    bool path_exists(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        if (list.get_iter(out iter, path))
            return true;
        else return false;
    }

    public void select_path(Gtk.TreePath path) {
        if (path_exists(path))
            select(path);
    }
    
    void insert_before(string item, Gtk.TreePath path) {
        Gtk.TreeIter new_iter;
        Gtk.TreeIter sibling;
        list.get_iter(out sibling, path);
        list.insert_before(out new_iter, sibling);
        list.set(new_iter, 0, item, -1);
    }

    void remove(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        list.get_iter(out iter, path);
        list.remove(iter);
    }

    public void collate(string[] new_list) {
        Gtk.TreePath current_path = new Gtk.TreePath.first();
        int new_list_index = 0;
        while (true) {
            string? item = get_item_at_path(current_path);
            if (item == null || new_list_index == new_list.length)
                break;
            string new_item = new_list[new_list_index];

            int result = strcmp(item, new_item);
            if (result > 0) {
                remove(current_path);
            } else {
                if (result != 0)
                    insert_before(new_list[new_list_index], current_path);
                current_path.next();
                ++new_list_index;
            }
        }

        // The rest of the items in the old list are not present, so remove them
        while (true) {
            if (!path_exists(current_path))
                break;
            remove(current_path);
        }

        // The rest of the items in the other list must be new, so add them
        for (; new_list_index < new_list.length; ++new_list_index)
            append(new_list[new_list_index]);
        
    }
    
}

//// Gedit helper functions ////

string? document_filename(Gedit.Document document) {
    string uri = document.get_uri();
    if (uri == null)
        return null;
    try {
        return Filename.from_uri(uri);
    } catch (ConvertError e) { return null; }
}

Gedit.Tab? find_tab(string filename, out Gedit.Window window) {
    string uri = filename_to_uri(filename);
    
    foreach (Gedit.Window w in Gedit.App.get_default().get_windows()) {
        Gedit.Tab tab = w.get_tab_from_uri(uri);
        if (tab != null) {
            window = w;
            return tab;
        }
    }
    return null;
}
