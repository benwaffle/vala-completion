/* Copyright 2009-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Gee;
using Vte;
using Valencia;

public abstract class Destination : Object {
    public abstract void get_range(Gtk.TextBuffer buffer,
                                   out Gtk.TextIter start, out Gtk.TextIter end);
}

class LineNumber : Destination {
    int line;    // starting from 0
    
    public LineNumber(int line) { this.line = line; }
    
    public override void get_range(Gtk.TextBuffer buffer,
                                   out Gtk.TextIter start, out Gtk.TextIter end) {
        Gtk.TextIter iter;
        buffer.get_iter_at_line(out iter, line);
        get_line_start_end(iter, out start, out end);
    }
}

class LineCharRange : Destination {
    int start_line;        // starting from 0
    int start_char;
    int end_line;
    int end_char;
    
    public LineCharRange(int start_line, int start_char, int end_line, int end_char) {
        this.start_line = start_line;
        this.start_char = start_char;
        this.end_line = end_line;
        this.end_char = end_char;
    }
    
    public override void get_range(Gtk.TextBuffer buffer,
                                   out Gtk.TextIter start, out Gtk.TextIter end) {
        start = iter_at_line_offset(buffer, start_line, start_char);
        end = iter_at_line_offset(buffer, end_line, end_char);
    }
}

class CharRange : Destination {
    int start_char;
    int end_char;
    
    public CharRange(int start_char, int end_char) {
        this.start_char = start_char;
        this.end_char = end_char;
    }
    
    public override void get_range(Gtk.TextBuffer buffer,
                                   out Gtk.TextIter start, out Gtk.TextIter end) {
        buffer.get_iter_at_offset(out start, start_char);
        buffer.get_iter_at_offset(out end, end_char);
    }    
}

class ScanInfo : Object {
    public ParseInfo parse_info;
    public Method? method;
    public int cursor_pos;
    
    public ScanInfo(Method? method, ParseInfo parse_info, int cursor_position) {
        this.method = method;
        this.parse_info = parse_info;
        cursor_pos = cursor_position;
    }
     
    public ScanInfo.empty() { }
    
    public Expression inner() { return parse_info.inner; }
    
    public Expression outer() { return parse_info.outer; }
}
  
public class Instance : Peas.ExtensionBase, Gedit.WindowActivatable {
    static Gee.ArrayList<Instance> instances = new Gee.ArrayList<Instance>();

	Gedit.Window _window;

	public Gedit.Window window {
	    construct { _window = value; }
	    owned get { return _window; }
	}
    
    Program last_program_to_build;

    Gtk.ActionGroup action_group;
    
    Gtk.MenuItem go_to_definition_menu_item;
    Gtk.MenuItem find_symbol_menu_item;
    Gtk.MenuItem go_to_outer_scope_menu_item;
    Gtk.MenuItem go_back_menu_item;
    Gtk.MenuItem go_forward_menu_item;
    Gtk.MenuItem next_error_menu_item;
    Gtk.MenuItem prev_error_menu_item;
    Gtk.MenuItem display_tooltip_menu_item;
    
    Gtk.MenuItem build_menu_item;
    Gtk.MenuItem clean_menu_item;
    Gtk.MenuItem run_menu_item;
    Gtk.MenuItem settings_menu_item;

    uint ui_id;
    
    int saving;
    bool child_process_running;

    // Output pane
    Gtk.TextTag error_tag;
    Gtk.TextTag italic_tag;
    Gtk.TextTag bold_tag;
    Gtk.TextTag highlight_tag;
    
    Gtk.TextBuffer output_buffer;
    Gtk.TextView output_view;
    Gtk.ScrolledWindow output_pane;
    
    delegate bool ProcessFinished();
    unowned ProcessFinished on_process_finshed;

    // Settings dialog
    ProjectSettingsDialog settings_dialog;

    // Parsing dialog
    ProgressBarDialog parsing_dialog;

    // Run command
    Gtk.ScrolledWindow run_pane;
    Vte.Terminal run_terminal;
    
    // Error pane 
    Regex error_regex;
    
    string target_filename;
    Destination destination;

    // Symbol pane
    SymbolBrowser symbol_browser;
    ulong symbol_browser_connect_id;

    // Jump to definition history
    static ArrayList<Gtk.TextMark> history;
    const int MAX_HISTORY = 10;
    int history_index;
    bool browsing_history;

    // Tooltips
    Tooltip tip;
    AutocompleteDialog autocomplete;

    // Signal handlers
    SignalConnection instance_connections;
    ArrayList<SignalConnection> tab_connections;

    // Display enclosing class in statusbar
    int old_cursor_offset;

    // Keeps track of all open documents' previous modified state
    static HashMap<weak Gedit.Document, bool> documents_modified_state = 
        new HashMap<weak Gedit.Document, bool>();

    Gedit.View view_to_scroll;
   
    // Menu item entries
    const Gtk.ActionEntry[] entries = {
        { "SearchGoToDefinition", null, "Go to _Definition", "F12",
          "Jump to a symbol's definition", on_go_to_definition },
        { "SearchFindSymbol", Gtk.Stock.FIND, "Find _Symbol...", "<ctrl><alt>s",
          "Search for a symbol by name", on_find_symbol },
        { "SearchGoToEnclosingMethod", null, "Go to _Outer Scope", "<ctrl>F12",
          "Jump to the enclosing method or class", on_go_to_outer_scope },
        { "SearchGoBack", Gtk.Stock.GO_BACK, "Go _Back", "<alt>Left",
          "Go back after jumping to a definition", on_go_back },
        { "SearchGoForward", Gtk.Stock.GO_FORWARD, "Go F_orward", "<alt>Right",
          "Go forward to a definition after jumping backwards", on_go_forward },
        { "SearchNextError", null, "_Next Error", "<ctrl><alt>e",
          "Go to the next compiler error in the ouput and view panes", on_next_error },
        { "SearchPrevError", null, "_Previous Error", "<ctrl><alt>p",
          "Go to the previous compiler error in the ouput and view panes", on_prev_error },
        { "SearchAutocomplete", null, "_AutoComplete", "<ctrl>space",
          "Display method or symbol information", on_display_tooltip_or_autocomplete },
        
        { "Project", null, "_Project" },   // top-level menu

        { "ProjectBuild", Gtk.Stock.CONVERT, "_Build", "<ctrl><alt>b",
          "Build the project", on_build },
        { "ProjectClean", Gtk.Stock.CLEAR, "_Clean", "<ctrl><alt>c",
          "Clean build output", on_clean },
        { "ProjectRun", Gtk.Stock.EXECUTE, "_Run", "<ctrl><alt>r",
          "Run the program", on_run },
        { "ProjectSettings", Gtk.Stock.PROPERTIES, "_Settings", "<ctrl><alt>t",
          "Customize the build and clean commands", on_project_settings },
        { "ProjectWipeValencia", null, "Wipe _Valencia Symbols", null,
          "Wipe Valencia's discovered symbols and rebuild", on_wipe_valencia }
    };

    const string ui = """
        <ui>
          <menubar name="MenuBar">
            <menu name="SearchMenu" action="Search">
              <placeholder name="SearchOps_8">
                <menuitem name="SearchGoToDefinitionMenu" action="SearchGoToDefinition"/>
                <menuitem name="SearchFindSymbolMenu" action="SearchFindSymbol"/>
                <menuitem name="SearchGoToEnclosingMethodMenu" action="SearchGoToEnclosingMethod"/>
                <menuitem name="SearchGoBackMenu" action="SearchGoBack"/>
                <menuitem name="SearchGoForwardMenu" action="SearchGoForward"/>
                <separator/>
                <menuitem name="SearchNextErrorMenu" action="SearchNextError"/>
                <menuitem name="SearchPrevErrorMenu" action="SearchPrevError"/>
                <separator/>
                <menuitem name="SearchAutocompleteMenu" action="SearchAutocomplete"/>
              </placeholder>
            </menu>
            <placeholder name="ExtraMenu_1">
              <menu name="ProjectMenu" action="Project">
                <menuitem name="ProjectBuildMenu" action="ProjectBuild"/>
                <menuitem name="ProjectCleanMenu" action="ProjectClean"/>
                <menuitem name="ProjectRunMenu" action="ProjectRun"/>
                <menuitem name="ProjectSettingsMenu" action="ProjectSettings"/>
                <separator/>
                <menuitem name="ProjectWipeValenciaMenu" action="ProjectWipeValencia"/>
              </menu>
            </placeholder>
          </menubar>
        </ui>
    """;    

    public Instance() {
        Object();
    }
    
    public void activate() {
        instances.add(this);

        if (history == null)
            history = new ArrayList<Gtk.TextMark>();
              
        // Settings dialog
        settings_dialog = new ProjectSettingsDialog(window);
        settings_dialog.settings_changed.connect(on_settings_changed);

        // Tooltips        
        tip = new Tooltip(window);
        autocomplete = new AutocompleteDialog(window);

        // Output pane
        output_buffer = new Gtk.TextBuffer(null);

        error_tag = output_buffer.create_tag("error", "foreground", "#c00");
        italic_tag = output_buffer.create_tag("italic", "style", Pango.Style.OBLIQUE);
        bold_tag = output_buffer.create_tag("bold", "weight", Pango.Weight.BOLD);
        highlight_tag = output_buffer.create_tag("highlight", "foreground", "black", "background", 
                                                 "#abd");
        output_view = new Gtk.TextView.with_buffer(output_buffer);
        output_view.set_editable(false);
        output_view.set_cursor_visible(false);
        Pango.FontDescription font = Pango.FontDescription.from_string("Monospace");
        output_view.override_font(font);
        output_view.button_press_event.connect(on_button_press);

        output_pane = new Gtk.ScrolledWindow(null, null);
        output_pane.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        output_pane.add(output_view);
        output_pane.show_all();

        Gedit.Panel panel = window.get_bottom_panel();
        panel.add_item_with_stock_icon(output_pane, "build", "Build", Gtk.Stock.CONVERT);

        // Run pane
        run_terminal = new Vte.Terminal();
        run_terminal.child_exited.connect(on_run_child_exit);
        child_process_running = false;
        
        run_pane = new Gtk.ScrolledWindow(null, null);
        run_pane.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        run_pane.add(run_terminal);
        run_pane.show_all();
        
        panel.add_item_with_stock_icon(run_pane, "run", "Run", Gtk.Stock.EXECUTE);     

        // Symbol pane
        symbol_browser = new SymbolBrowser(this);
        symbol_browser_connect_id = Signal.connect(window, "active-tab-changed", 
            (Callback) SymbolBrowser.on_active_tab_changed, symbol_browser);
        symbol_browser.activate();

        // Enclosing class in statusbar
        old_cursor_offset = 0;

        // Signal connections
        instance_connections = new SignalConnection(this);
        tab_connections = new ArrayList<SignalConnection>();
        
        // Toolbar menu
        Gtk.UIManager manager = window.get_ui_manager();
        
        action_group = new Gtk.ActionGroup("valencia");
        action_group.add_actions(entries, this);
        manager.insert_action_group(action_group, 0);
        
        try {
            ui_id = manager.add_ui_from_string(ui, -1);
        } catch (Error e) {
            error("error in add_ui_from_string: %s", e.message);
        }
        
        initialize_menu_items(manager);
        init_error_regex();

        instance_connections.add_signal(window, "tab-added", (Callback) tab_added_callback, this);
        instance_connections.add_signal(window, "tab-removed", (Callback) tab_removed_callback, this);

        foreach (Gedit.Document document in window.get_documents()) {
            tab_added_callback(window, Gedit.Tab.get_from_document(document), this);
        }
    }

    public static Instance? find(Gedit.Window window) {
        foreach (Instance i in instances)
            if (i.window == window)
                return i;
        return null;
    }
    
    void initialize_menu_items(Gtk.UIManager manager) {
        Gtk.MenuItem search_menu = get_menu_item(manager, "/MenuBar/SearchMenu");
        search_menu.activate.connect(on_search_menu_activated);
        
        Gtk.MenuItem project_menu = get_menu_item(manager, "/MenuBar/ExtraMenu_1/ProjectMenu");
        project_menu.activate.connect(on_project_menu_activated);
        
        go_to_definition_menu_item = get_menu_item(manager,
            "/MenuBar/SearchMenu/SearchOps_8/SearchGoToDefinitionMenu");
        
        find_symbol_menu_item = get_menu_item(manager,
            "/MenuBar/SearchMenu/SearchOps_8/SearchFindSymbolMenu");
        
        go_to_outer_scope_menu_item = get_menu_item(manager,
            "/MenuBar/SearchMenu/SearchOps_8/SearchGoToEnclosingMethodMenu");
        
        go_back_menu_item = get_menu_item(manager,
            "/MenuBar/SearchMenu/SearchOps_8/SearchGoBackMenu");
        
        go_forward_menu_item = get_menu_item(manager, 
            "/MenuBar/SearchMenu/SearchOps_8/SearchGoForwardMenu");

        next_error_menu_item = get_menu_item(manager, 
            "/MenuBar/SearchMenu/SearchOps_8/SearchNextErrorMenu");
        
        prev_error_menu_item = get_menu_item(manager,
            "/MenuBar/SearchMenu/SearchOps_8/SearchPrevErrorMenu");
        
        display_tooltip_menu_item = get_menu_item(manager,
            "/MenuBar/SearchMenu/SearchOps_8/SearchAutocompleteMenu");
        
        build_menu_item = get_menu_item(manager,
            "/MenuBar/ExtraMenu_1/ProjectMenu/ProjectBuildMenu");
        
        clean_menu_item = get_menu_item(manager,
            "/MenuBar/ExtraMenu_1/ProjectMenu/ProjectCleanMenu");
        
        run_menu_item = get_menu_item(manager,
            "/MenuBar/ExtraMenu_1/ProjectMenu/ProjectRunMenu");

        settings_menu_item = get_menu_item(manager, 
              "/MenuBar/ExtraMenu_1/ProjectMenu/ProjectSettingsMenu");
    }

    static void tab_added_callback(Gedit.Window window, Gedit.Tab tab, Instance instance) {
        Gedit.Document document = tab.get_document();
        documents_modified_state.set(document, false);
    
        SignalConnection connection = new SignalConnection(tab);
        instance.tab_connections.add(connection);

        // Hook up this particular tab's view with tooltips
        Gedit.View tab_view = tab.get_view();
        connection.add_signal(tab_view, "key-press-event", (Callback) key_press_callback, instance);
        connection.add_signal(tab_view, "show-completion",
            (Callback) show_completion_callback, instance);

        Gtk.Widget widget = tab_view.get_parent();
        Gtk.ScrolledWindow scrolled_window = widget as Gtk.ScrolledWindow;
        assert(scrolled_window != null);
        
        Gtk.Adjustment vert_adjust = scrolled_window.get_vadjustment();
        connection.add_signal(vert_adjust, "value-changed", (Callback) scrolled_callback, instance);

        connection.add_signal(document, "saved", (Callback) all_save_callback, instance);
        connection.add_signal(document, "insert-text", (Callback) text_inserted_callback, instance, true);
        connection.add_signal(document, "delete-range", (Callback) text_deleted_callback, instance, true);
        connection.add_signal(document, "cursor-moved", (Callback) cursor_moved_callback, instance, true);
        
        connection.add_signal(tab_view, "focus-out-event", (Callback) focus_off_view_callback, instance);
        connection.add_signal(tab_view, "button-press-event", (Callback) button_press_callback, instance);
    }

    static void tab_removed_callback(Gedit.Window window, Gedit.Tab tab, Instance instance) {
        weak Gedit.Document removed_document = tab.get_document();
        bool document_exists_in_map = documents_modified_state.unset(removed_document);
        assert(document_exists_in_map);

        foreach (SignalConnection connection in instance.tab_connections) {
            if (connection.base_instance == tab) {
                instance.tab_connections.remove(connection);
                break;
            }
        }
    
        Gedit.Document document = tab.get_document();

        if (document.get_modified()) {
            // We're closing a document without saving changes.  Reparse the symbol tree
            // from the source file on disk (if the file exists on disk).
            string path = document_filename(document);
            if (path != null && FileUtils.test(path, FileTest.EXISTS))
                Program.update_any(path, null);
        }
    }
    
    static void scrolled_callback(Gtk.Adjustment adjust, Instance instance) {
        instance.tip.hide();
        instance.autocomplete.hide();
    }

    static void show_completion_callback(Gedit.View view, Instance instance) {
        instance.on_display_tooltip_or_autocomplete();
    }

    static bool key_press_callback(Gedit.View view, Gdk.EventKey key, Instance instance) {
        bool handled = false; 
        
        // These will always catch, even with alt and ctrl modifiers
        switch(Gdk.keyval_name(key.keyval)) {
            case "Escape":
                if (instance.autocomplete.is_visible())
                    instance.autocomplete.hide();
                else
                    instance.tip.hide();
                handled = true;
                break;
            case "Up":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.select_previous();
                    handled = true;
                }
                break;
            case "Down":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.select_next();
                    handled = true;
                }
                break;
                
            // We handle Alt+Left and Alt+Right explicitly to override GtkSourceView, which
            // normally uses these as shortcuts for moving the selected word left or right.
            case "Left":
                if (key.state == Gdk.ModifierType.MOD1_MASK) {
                    instance.on_go_back();
                    handled = true;
                }
                break;
            case "Right":
                if (key.state == Gdk.ModifierType.MOD1_MASK) {
                    instance.on_go_forward();
                    handled = true;
                }
                break;
                
            case "Home":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.select_first_cell();
                    handled = true;
                }
                break;
            case "End":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.select_last_cell();
                    handled = true;
                }
                break;
            case "Page_Up":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.page_up();
                    handled = true;
                }
                break;
            case "Page_Down":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.page_down();
                    handled = true;
                }
                break;
            case "Return":
                if (instance.autocomplete.is_visible()) {
                    instance.autocomplete.select_item();
                    handled = true;
                }
                break;
            default:
                break;
        }
        
        return handled;
    }

    static bool focus_off_view_callback(Gedit.View view, Gdk.EventFocus focus, Instance instance) {
        instance.tip.hide();
        instance.autocomplete.hide();
        
        // Make sure to display the new enclosing class when switching tabs
        instance.old_cursor_offset = 0;
        instance.update_status_bar();
        
        // Let other handlers catch this event as well
        return false;
    }

    static void text_inserted_callback(Gedit.Document doc, Gtk.TextIter iter, string text,
                                       int length, Instance instance) {
        if (instance.autocomplete.is_visible()) {
            if (text.get_char().isspace())
                instance.autocomplete.hide();
            else
                instance.display_autocomplete(instance.get_scan_info(true));
        }

        if (instance.tip.is_visible()) {
            if (text == ")" || text == "(") {
                instance.tip.hide();
                instance.autocomplete.hide();
                instance.display_tooltip(instance.get_scan_info(true));
            } 
        }
    }

    static void text_deleted_callback(Gedit.Document doc, Gtk.TextIter start, Gtk.TextIter end,
                                      Instance instance) {
        if (instance.tip.is_visible()) {
            string line = instance.tip.get_method_line();
            if (!line.contains(instance.tip.get_method_name() + "("))
                instance.tip.hide(); 
        }
        
        if (instance.autocomplete.is_visible()) {
            instance.autocomplete.hide();
            instance.on_display_tooltip_or_autocomplete();
        }
    }
    
    static void cursor_moved_callback(Gedit.Document doc, Instance instance) {
        instance.update_status_bar();
    }

    static bool button_press_callback(Gedit.View view, Gdk.EventButton event, Instance instance) {
        instance.tip.hide();
        instance.autocomplete.hide();

        // Let other handlers catch this event as well
        return false;
    }

    // TODO: Merge this method with saved_callback, below.
    static void all_save_callback(Gedit.Document document, void *arg1, Instance instance) {
        string path = document_filename(document);
        Program.update_any(path, buffer_contents(document));
        instance.symbol_browser.on_document_saved();
    }
    
    bool scroll_to_end() {
        Gtk.TextIter end;
        output_buffer.get_end_iter(out end);
        output_view.scroll_to_iter(end, 0.25, false, 0.0, 0.0);
        return false;
    }
    
    bool on_build_output(IOChannel source, bool error) {
        bool ret = true;
        bool appended = false;
        while (true) {
            string line;
            size_t length;
            size_t terminator_pos;
            IOStatus status;
            try {
                status = source.read_line(out line, out length, out terminator_pos);
            } catch (ConvertError e) {
                return false;   // TODO: report error
            } catch (IOChannelError e) {
                return false;   // TODO: report error
            }
            if (status == IOStatus.EOF) {
                if (error) {
                    appended = on_process_finshed();
                }
                ret = false;
                break;
            }
            if (status != IOStatus.NORMAL)
                break;
            append_with_tag(output_buffer, line, error ? error_tag : null);
            appended = true;
        }
        if (appended)
            Idle.add(scroll_to_end);
        return ret;
    }
    
    bool on_build_stdout(IOChannel source, IOCondition condition) {
        return on_build_output(source, false);
    }
    
    bool on_build_stderr(IOChannel source, IOCondition condition) {
        return on_build_output(source, true);
    }
    
    bool on_build_finished() {
        append_with_tag(output_buffer, "\nBuild complete", italic_tag);

        // Always regenerate the list *after* a new build
        generate_error_history(last_program_to_build);
        return true;
    }
  
    void hide_old_build_output() {
        foreach (Instance instance in instances) {
            if (instance != this && last_program_to_build == instance.last_program_to_build) {
                instance.output_pane.hide();
                instance.last_program_to_build = null;
            }
        }
    }
    
    string get_active_document_filename() {
        Gedit.Document document = window.get_active_document();
        return document_filename(document);
    }
    
    void show_output_pane() {
        output_pane.show();
        Gedit.Panel panel = window.get_bottom_panel();
        panel.activate_item(output_pane);
        panel.show();
    }
    
    void spawn_process(string command, string working_directory, ProcessFinished callback) {
        string[] argv;
        
        try {
            if (!Shell.parse_argv(command, out argv)) {
                warning("can't parse command arguments");
                return;
            }
        } catch (ShellError e) {
            warning("error parsing command arguments: %s", e.message);
            return;
        }
        
        on_process_finshed = callback;
        output_buffer.set_text("", 0);
        
        output_pane.show();
        Gedit.Panel panel = window.get_bottom_panel();
        panel.activate_item(output_pane);
        panel.show();
        
        Pid child_pid;
        int input_fd;
        int output_fd;
        int error_fd;
        try {
        Process.spawn_async_with_pipes(
            working_directory,    // working directory
            argv,
            null,   // environment
            SpawnFlags.SEARCH_PATH,
            null,   // child_setup
            out child_pid,
            out input_fd,
            out output_fd,
            out error_fd);
        } catch (SpawnError e) {
            append_with_tag(output_buffer, "Could not execute ", italic_tag);
            append_with_tag(output_buffer, argv[0], bold_tag);
            append_with_tag(output_buffer, " in ", italic_tag);
            append_with_tag(output_buffer, working_directory, bold_tag);
            return;
        }
        
        try {
            make_pipe(output_fd, on_build_stdout);
            make_pipe(error_fd, on_build_stderr);        
        } catch (IOChannelError e) {
            append_with_tag(output_buffer, "There was an I/O error trying to run ", italic_tag);
            append_with_tag(output_buffer, argv[0], bold_tag);
            append_with_tag(output_buffer, " in ", italic_tag);
            append_with_tag(output_buffer, working_directory, bold_tag);
            return;
        }

        append_with_tag(output_buffer, "Running ", italic_tag);
        append_with_tag(output_buffer, command, bold_tag);
        append_with_tag(output_buffer, " in ", italic_tag);
        append_with_tag(output_buffer, working_directory, bold_tag);
        append(output_buffer, "\n\n");
    }

    void build() {
        string filename = get_active_document_filename();

        if (filename == null)
            return;

        Program.rescan_build_root(filename);

        // Record the last program to build in this window so that we don't accidentally hide
        // output that isn't part of a program that gets built later
        last_program_to_build = Program.find_containing(filename);

        hide_old_build_output();

        string command = last_program_to_build.config_file.get_build_command();

        spawn_process(command, last_program_to_build.get_top_directory(), on_build_finished);
    }

    void on_saved() {
        if (--saving == 0)
            build();
    }

    static void saved_callback(Gedit.Document document, void *arg1, Instance instance) {
        SignalHandler.disconnect_by_func(document, (void *) saved_callback, instance);
        instance.on_saved();
    }
    
    void on_build() {
        foreach (Gedit.Document d in ((Gedit.App) Application.get_default()).get_documents())
            if (!d.is_untitled() && d.get_modified()) {
                ++saving;
                Signal.connect(d, "saved", (Callback) saved_callback, this);
                d.do_save(0);
            }
        if (saving == 0)
            build();
    }

    bool scroll_view_to_cursor() {
        if (view_to_scroll != null) {
            view_to_scroll.scroll_to_cursor();
            view_to_scroll = null;
        }
        return false;
    }

    void go(Gedit.Tab tab, Destination dest) {
        Gedit.Document document = tab.get_document();
        Gtk.TextIter start;
        Gtk.TextIter end;
        dest.get_range(document, out start, out end);
        document.select_range(start, end);

        // We need to scroll to the selection in an idle handler.  If we don't, then when 
        // a new document is being loaded sometimes the scrolling won't happen at all,
        // especially if the document is long.  This was http://trac.yorba.org/ticket/1000 .
        view_to_scroll = tab.get_view();
        Idle.add(scroll_view_to_cursor);
    }
    
    void on_document_loaded(Gedit.Document document) {
        if (document_filename(document) == target_filename) {
            Gedit.Tab tab = Gedit.Tab.get_from_document(document);
            go(tab, destination);
            target_filename = null;
            destination = null;
        }
    }

    static void document_loaded_callback(Gedit.Document document, void *arg1, Instance instance) {
        instance.on_document_loaded(document);
    }

    public void jump(string filename, Destination dest) {
        Gedit.Window w;
        Gedit.Tab tab = find_tab(filename, out w);
        if (tab != null) {
            w.set_active_tab(tab);
            w.present();            
            go(tab, dest);
            return;
        }
        
        Gedit.Encoding encoding = null;
        tab = window.create_tab_from_location(File.new_for_path(filename), encoding, 0, 0, false, true);
        target_filename = filename;
        destination = dest;
        Signal.connect(tab.get_document(), "loaded", (Callback) document_loaded_callback, this);
    }
    
    // We look for two kinds of error lines:
    //   foo.vala:297.15-297.19: ...  (valac errors)
    //   foo.c:268: ...               (GCC errors, containing a line number only)
    void init_error_regex() {
        try {
            error_regex = new Regex("""^(.*):(\d+)(?:\.(\d+)-(\d+)\.(\d+))?:""");
        } catch (RegexError e) {
            stderr.puts("A RegexError occured when creating a new regular expression.\n");
            return;        // TODO: report error
        }
    }
  
    string get_line(Gtk.TextIter iter) {
        Gtk.TextIter start;
        Gtk.TextIter end;
        weak Gtk.TextBuffer buffer = iter.get_buffer();
        get_line_start_end(iter, out start, out end);
        return buffer.get_text(start, end, true);
    }
    
    // Look for error position information in the line containing the given iterator.
    ErrorInfo? error_info(Gtk.TextIter iter) {
        string line = get_line(iter);
        MatchInfo info;
        if (error_regex.match(line, 0, out info)) {
            ErrorInfo e = new ErrorInfo();
            e.filename = info.fetch(1);
            e.start_line = info.fetch(2);
            e.start_char = info.fetch(3);
            e.end_line = info.fetch(4);
            e.end_char = info.fetch(5);
            return e;
        }
        else return null;
    }
  
    // Return true if s is composed of ^^^ characters pointing to an error snippet above.
    bool is_snippet_marker(string s) {
        weak string p = s;
        while (p != "") {
            unichar c = p.get_char();
            if (!c.isspace() && c != '^')
                return false;
            p = p.next_char();
        }
        return true;
    }
    
    void tag_text_buffer_line(Gtk.TextBuffer buffer, Gtk.TextTag tag, Gtk.TextIter iter) {
        Gtk.TextIter start;
        Gtk.TextIter end;
        buffer.get_bounds(out start, out end);
        buffer.remove_tag(tag, start, end);
        get_line_start_end(iter, out start, out end);
        buffer.apply_tag(tag, start, end);
    }

    void jump_to_document_error(Gtk.TextIter iter, ErrorInfo info, Program program) {
        int line_number = int.parse(info.start_line);
        Destination dest;
        if (info.start_char == null)
            dest = new LineNumber(line_number - 1);
        else
            dest = new LineCharRange(line_number - 1, int.parse(info.start_char) - 1,
                                     int.parse(info.end_line) - 1, int.parse(info.end_char));

        if (Path.is_absolute(info.filename)) {
            jump(info.filename, dest);
        } else {
            string filename = program.get_path_for_filename(info.filename);
             if (filename == null)
                return;
            jump(filename, dest);
        }
    }

////////////////////////////////////////////////////////////
//                   Jump to Definition                   //
////////////////////////////////////////////////////////////

    void add_mark_at_insert_to_history() {
        Gedit.Document doc = window.get_active_document();
        Gtk.TextIter insert = get_insert_iter(doc);
            
        // Don't add a mark to history if the most recent mark is on the same line
        if (history.size > 0) {
            Gtk.TextMark old_mark = history.get(history.size - 1);
            Gedit.Document old_doc = (Gedit.Document) old_mark.get_buffer();

            if (old_doc == doc) {
                Gtk.TextIter old_iter;
                old_doc.get_iter_at_mark(out old_iter, old_mark);
                if (old_iter.get_line() == insert.get_line())
                    return;
            }
        }

        Gtk.TextMark mark = doc.create_mark(null, insert, false);
        history.add(mark);
        if (history.size > MAX_HISTORY)
            history.remove_at(0);
        history_index = history.size; // always set the current index to be at the top
    }
    
    void add_insert_cursor_to_history() {
        // Make sure the current index is the last element
        while (history.size > 0 && history.size > history_index)
            history.remove_at(history.size - 1);

        add_mark_at_insert_to_history();
        browsing_history = false;
    }
    
    public void reparse_modified_documents(string filename) {
        Program program = Program.find_containing(filename, true);

        foreach (Gedit.Document document in ((Gedit.App) Application.get_default()).get_documents()) {
            assert(documents_modified_state.has_key(document));
            bool previously_modified = documents_modified_state.get(document);
            bool currently_modified = document.get_modified();
            documents_modified_state.set(document, currently_modified);
            
            if (!currently_modified && !previously_modified)
                continue;
            
            string path = document_filename(document);
            if (path != null)
                program.update(path, buffer_contents(document));
        }
    }
    
    void get_buffer_contents_and_position(string filename, out string source, out int pos) {
        reparse_modified_documents(filename);
        
        Gedit.Document document = window.get_active_document();
        source = buffer_contents(document);
        Gtk.TextIter insert = get_insert_iter(document);
        pos = insert.get_offset();
    }

    void on_go_to_definition() {
        string? filename = active_filename();
        if (filename == null || !Program.is_vala(filename))
            return;

        Program program = Program.find_containing(filename, true);
        
        if (program.is_parsing()) {
            program.parsed_file.connect(update_parse_dialog);
            program.system_parse_complete.connect(jump_to_symbol_definition);
        } else jump_to_symbol_definition();
    }

    void jump_to_symbol_definition() {
        string? filename = active_filename();
        if (filename == null)
            return;
            
        string source;
        int pos;
        get_buffer_contents_and_position(filename, out source, out pos);

        ScanInfo info = get_scan_info(false);
        if (info == null || info.inner() == null)
            return;

        Program program = Program.find_containing(filename);
        SourceFile sf = program.find_source(filename);
        Symbol? sym = sf.resolve(info.inner(), pos, false);
        if (sym == null)
            return;

        add_insert_cursor_to_history();

        SourceFile dest = sym.source;
        jump(dest.filename, new CharRange(sym.start, sym.start + sym.name_length()));
    }
    
    void on_go_to_outer_scope() {
        string? filename = active_filename();
        if (filename == null || !Program.is_vala(filename))
            return;

        string source;
        int pos;
        get_buffer_contents_and_position(filename, out source, out pos);

        ScanScope? scan_scope = new Parser().find_enclosing_scope(source, pos, false);
        if (scan_scope == null)
            return;
        
        add_insert_cursor_to_history();
        
        jump(filename, new CharRange(scan_scope.start_pos, scan_scope.end_pos));
    }

    void on_go_back() {
        if (history.size == 0)
            return;

        // Preserve place in history
        if (history_index == history.size && !browsing_history) {
            add_mark_at_insert_to_history();
            browsing_history = true;
        }
        
        if (history_index <= 1)
            return;

        --history_index;
        scroll_to_history_index();
    }

    void on_go_forward() {
        if (history.size == 0 || history_index >= history.size)
            return;

        ++history_index;
        scroll_to_history_index();
    }

    void scroll_to_history_index() {
        Gtk.TextMark mark = history.get(history_index - 1);
        assert(!mark.get_deleted());
        
        Gedit.Document buffer = (Gedit.Document) mark.get_buffer();
        string filename = document_filename(buffer);
        Gtk.TextIter iter;
        buffer.get_iter_at_mark(out iter, mark);
        int offset = iter.get_offset();
        jump(filename, new CharRange(offset, offset));
    }

    bool can_go_back() {
        if (history.size == 0 || history_index <= 1)
            return false;

        // -2 because history_index is not 0-based (it is 1-based), and we need the previous element
        Gtk.TextMark mark = history.get(history_index - 2);

        return !mark.get_deleted();
    }

    bool can_go_forward() {
        if (history.size == 0 || history_index >= history.size)
            return false;

        Gtk.TextMark mark = history.get(history_index);
        return !mark.get_deleted();
    }

////////////////////////////////////////////////////////////
//                      Jump to Error                     //
////////////////////////////////////////////////////////////

    void update_error_history_index(ErrorList program_errors, ErrorInfo info) {
        program_errors.error_index = -1;
        foreach (ErrorPair pair in program_errors.errors) {
            ++program_errors.error_index;
            
            if (info.start_line == pair.error_info.start_line)
                return;
        }
    }

    bool on_button_press(Gdk.EventButton event) {
        if (event.type != Gdk.EventType.2BUTTON_PRESS)  // double click?
            return false;   // return if not
        Gtk.TextIter iter = get_insert_iter(output_buffer);
        ErrorInfo info = error_info(iter);
        if (info == null) {
            // Is this an error snippet?
            Gtk.TextIter next = iter;
            if (!next.forward_line() || !is_snippet_marker(get_line(next)))
                return false;
            
            // Yes; look for error information on the previous line.
            Gtk.TextIter prev = iter;
            if (prev.backward_line())
                info = error_info(prev);
        }
        if (info == null)
            return false;

        tag_text_buffer_line(output_buffer, highlight_tag, iter);
        
        // It is last_program_to_build because the output window being clicked on is obviously
        // from this same instance, which means the last program output to this instance's buffer
        jump_to_document_error(iter, info, last_program_to_build);
        update_error_history_index(last_program_to_build.error_list, info);

        return true;
    }

    public string active_filename() {
        Gedit.Document document = window.get_active_document();
        return document == null ? null : document_filename(document);
    }
    
    void clear_error_list(Gee.ArrayList<ErrorPair> error_list) {
        if (error_list == null || error_list.size == 0)
            return;

        // Before clearing the ArrayList, clean up the TextMarks stored in the buffers
        foreach (ErrorPair pair in error_list) {
            Gtk.TextMark mark = pair.document_pane_error;
            Gtk.TextBuffer buffer = mark.get_buffer();
            buffer.delete_mark(mark);

            mark = pair.build_pane_error;
            buffer = mark.get_buffer();
            buffer.delete_mark(mark);    
        }
       
        error_list.clear();
    }

    void generate_error_history(Program program) {
        if (program.error_list == null)
            program.error_list = new ErrorList();
        clear_error_list(program.error_list.errors);

        // Starting at the first line, search for errors downward
        Gtk.TextIter iter = get_insert_iter(output_buffer);
        iter.set_line(0);
        ErrorInfo einfo;
        program.error_list.error_index = -1;
        bool end_of_buffer = false;
        
        while (!end_of_buffer) {
            // Check the current line for errors
            einfo = error_info(iter);
            if (einfo != null) {
                Gedit.Document document = window.get_active_document();
                Gtk.TextIter document_iter;
                document.get_iter_at_line(out document_iter, int.parse(einfo.start_line));
              
                Gtk.TextMark doc_mark = document.create_mark(null, document_iter, false);
                Gtk.TextMark build_mark = output_buffer.create_mark(null, iter, false);
                
                ErrorPair pair = new ErrorPair(doc_mark, build_mark, einfo);
                program.error_list.errors.add(pair);
            }                
            
            end_of_buffer = !iter.forward_line();
        }
    }

    Instance? find_build_instance(string cur_top_directory) {
        foreach (Instance inst in instances) {
            if (inst.last_program_to_build != null && 
                inst.last_program_to_build.get_top_directory() == cur_top_directory) {
                    return inst;
                }
        }
        
        return null;
    }
    
    void move_output_mark_into_focus(Gtk.TextMark mark) {
        Gtk.TextBuffer output = mark.get_buffer();
        Gtk.TextIter iter;
        output.get_iter_at_mark(out iter, mark);
        output_view.scroll_to_iter(iter, 0.25, true, 0.0, 0.0);
        
        show_output_pane();
        tag_text_buffer_line(output_buffer, highlight_tag, iter);
    }

    void move_to_error(Program program) {
        ErrorPair pair = program.error_list.errors[program.error_list.error_index];

        Gtk.TextBuffer document = pair.document_pane_error.get_buffer();
        Gtk.TextIter doc_iter;
        document.get_iter_at_mark(out doc_iter, pair.document_pane_error);
        
        Instance target = find_build_instance(program.get_top_directory());
        if (target == null)
            return;

        jump_to_document_error(doc_iter, pair.error_info, program);
        target.move_output_mark_into_focus(pair.build_pane_error);
    }
    
    Program get_active_document_program() {
        string filename = active_filename();
        return Program.find_containing(filename);
    }

    public bool active_document_is_vala_file() {
        string filename = active_filename();
        return filename != null && Program.is_vala(filename);
    }
        
    void on_next_error() {
        if (active_filename() == null)
            return;
    
        Program program = get_active_document_program();
        
        if (program.error_list == null || program.error_list.errors.size == 0)
            return;
    
        if (program.error_list.error_index < program.error_list.errors.size - 1)
            ++program.error_list.error_index;
        
        move_to_error(program);
    }

    void on_prev_error() {
        if (active_filename() == null)
            return;
    
        Program program = get_active_document_program();
        
        if (program.error_list == null || program.error_list.errors.size == 0)
            return;
    
        if (program.error_list.error_index > 0)
            --program.error_list.error_index;
        
        move_to_error(program);
    }

////////////////////////////////////////////////////////////
//                      Run Command                       //
////////////////////////////////////////////////////////////

    void on_run() {
        if (active_filename() == null || child_process_running)
            return;

        string filename = get_active_document_filename();
        Program.rescan_build_root(filename);
        
        Program program = get_active_document_program();
        program.reparse_makefile();
        string binary_path = program.get_binary_run_path();
        
        if (binary_path == null || !program.get_binary_is_executable())
            return;

        if (!GLib.FileUtils.test(binary_path, GLib.FileTest.EXISTS)) {
            show_error_dialog("\"" + binary_path + "\" was not found. Try rebuilding. ");
            return;
        }
        
        if (!GLib.FileUtils.test(binary_path, GLib.FileTest.IS_EXECUTABLE)) {
            show_error_dialog("\"" + binary_path + "\" is not an executable file! ");
            return;
        }

        string[] args = { binary_path };
        
        int pid;
        bool ok;
        try {
            ok = run_terminal.fork_command_full(
                0, Path.get_dirname(binary_path), args, null, 0, null, out pid);
        } catch (Error e) { ok = false; }
        if (!ok) {
            show_error_dialog("can't fork command");
            return;
        }

        if (pid == -1) {
            show_error_dialog("There was a problem running \"" + binary_path + "\"");
            return;
        }

        run_terminal.reset(true, true);
        run_pane.show();
        Gedit.Panel panel = window.get_bottom_panel();
        panel.activate_item(run_pane);
        panel.show();
        
        child_process_running = true;
    }

    void on_run_child_exit() {
        run_terminal.feed("\r\nThe program exited.\r\n".data);
        child_process_running = false;
    }

////////////////////////////////////////////////////////////
//                  Progress bar update                   //
////////////////////////////////////////////////////////////

    void update_parse_dialog(double percentage) {
        if (percentage == 1.0) {
            if (parsing_dialog != null) {
                parsing_dialog.destroy();
                parsing_dialog = null;
            }
            return;
        }

        if (parsing_dialog == null)
            parsing_dialog = new ProgressBarDialog(window, "Parsing Vala files");

        parsing_dialog.set_percentage(percentage);
    }

////////////////////////////////////////////////////////////
//                   Status bar update                    //
////////////////////////////////////////////////////////////

    // If the range (old_cursor_offset, new_cursor_offset) contains a brace character
    // then update old_cursor_offset and return true.
    //
    // We don't want to allocate memory here since this code runs every time the
    // cursor moves.
    bool cursor_moved_outside_old_scope(string buffer, int new_cursor_offset) {
        int old = int.min(old_cursor_offset, buffer.char_count());     // in case buffer has shrunk
        
        long s = buffer.index_of_nth_char(int.min(old, new_cursor_offset));
        long end = buffer.index_of_nth_char(int.max(old, new_cursor_offset));
        
        while (s < end) {
            unichar c = buffer.get_char(s);
            if (c == '{' || c == '}') {
                old_cursor_offset = new_cursor_offset;
                return true;
            }
            s = next_utf8_char(buffer, s);
        }
        
        return false;
    }

    void update_status_bar() {
        string? filename = active_filename();
        if (filename == null || !Program.is_vala(filename))
            return;

        Gedit.Document document = window.get_active_document();
        string source = buffer_contents(document);
        Gtk.TextIter insert = get_insert_iter(document);
        int pos = insert.get_offset();
        
        // Don't reparse if the cursor hasn't moved past a '{' or a '}'
        if (!cursor_moved_outside_old_scope(source, pos))
            return;

        ScanScope? scan_scope = new Parser().find_enclosing_scope(source, pos, true);
        string class_name;
        if (scan_scope == null)
            class_name = "";
        else
            class_name = source.substring(scan_scope.start_pos, 
                                          scan_scope.end_pos - scan_scope.start_pos);
        
        Gtk.Statusbar bar = (Gtk.Statusbar) window.get_statusbar();
        bar.push(bar.get_context_id("Valencia"), class_name);
    }

////////////////////////////////////////////////////////////
//                 Tooltip/Autocomplete                   //
////////////////////////////////////////////////////////////

    void on_display_tooltip_or_autocomplete() {
        string? filename = active_filename();
        if (filename == null || !Program.is_vala(filename))
            return;

        Program program = Program.find_containing(filename, true);

        if (program.is_parsing()) {
            program.parsed_file.connect(update_parse_dialog);
            program.system_parse_complete.connect(display_tooltip_or_autocomplete);
        } else display_tooltip_or_autocomplete();
    }

    void display_tooltip(ScanInfo info) {
        if (info == null)
            return;
    
        if (info.method != null)
            tip.show(info.outer().to_string(), " " + info.method.to_string() + " ", 
                     info.parse_info.outer_pos);
    }

    void display_autocomplete(ScanInfo info) {
        if (info == null)
            return;

        Expression e = info.inner();
        
        if (e == null) {
            if (info.method != null)
                return;
            e = new Id("");
        }

        string? filename = active_filename();
        Program program = Program.find_containing(filename);
        SourceFile sf = program.find_source(filename);

        SymbolSet symbol_set = sf.resolve_prefix(e, info.cursor_pos, false);
        autocomplete.show(symbol_set);
    }

    void display_tooltip_or_autocomplete() {
        ScanInfo info = get_scan_info(true);
        display_tooltip(info);
        display_autocomplete(info);
    }

    ScanInfo? get_scan_info(bool partial) {
        Method? method;
        ParseInfo parse_info;
        int cursor_pos;
    
        string? filename = active_filename();
        string source;
        get_buffer_contents_and_position(filename, out source, out cursor_pos); 

        parse_info = new ExpressionParser(source, cursor_pos, partial).parse();

        Program program = Program.find_containing(filename);
        SourceFile sf = program.find_source(filename);
        // The sourcefile may be null if the file is a vala file but hasn't been saved to disk
        if (sf == null)
            return null;

        // Give the method tooltip precedence over autocomplete
        method = null;
        if (parse_info.outer != null && 
            (!tip.is_visible() || cursor_is_inside_different_function(parse_info.outer_pos))) {
            Symbol? sym = sf.resolve(parse_info.outer, cursor_pos, false);
            if (sym != null)
                method = sym as Method; 
        }

        return new ScanInfo(method, parse_info, cursor_pos);
    }

    bool cursor_is_inside_different_function(int method_pos) {
        Gtk.TextIter begin_iter = tip.get_iter_at_method();

        Gedit.Document document = window.get_active_document();
        Gtk.TextIter end_iter;
        document.get_iter_at_offset(out end_iter, method_pos);

        if (begin_iter.get_offset() > end_iter.get_offset()) {
            Gtk.TextIter temp;
            temp = begin_iter; 
            begin_iter = end_iter;
            end_iter = temp;
        }

        // Make sure the last character is a '(', since the method_pos offset will always be the
        // character before the '(' in a function call
        end_iter.forward_char();

        int left_parens = 0;
        begin_iter.forward_char();
        while (begin_iter.get_offset() <= end_iter.get_offset()) {
            unichar c = begin_iter.get_char();
            if (c == ')') {
                if (--left_parens != 0)
                    return true;
            } else if (c == '(') {
                ++left_parens;
            }
            
            begin_iter.forward_char();
        }
            
        return left_parens != 0;
    }

////////////////////////////////////////////////////////////
//                   Project settings                     //
////////////////////////////////////////////////////////////

    void on_project_settings() {
        string filename = active_filename();

        if (filename != null)
            settings_dialog.show(filename);
    }
    
    void on_wipe_valencia() {
        Program.wipe();
    }
    
    void on_settings_changed(string new_build_command, string new_clean_command, string new_pkg_blacklist) {
        Program program = get_active_document_program();
        program.config_file.update(new_build_command, new_clean_command, new_pkg_blacklist);
    }

////////////////////////////////////////////////////////////
//                      Find Symbol                       //
////////////////////////////////////////////////////////////

    void on_find_symbol() {
        string filename = active_filename();
        if (filename == null || !Program.is_vala(filename))
            return;
    
        symbol_browser.set_parent_instance_focus();
    }
    
////////////////////////////////////////////////////////////
//                    Clean command                       //
////////////////////////////////////////////////////////////

bool on_clean_finished() {
    append_with_tag(output_buffer, "\nClean complete", italic_tag);
    return true;
}

void on_clean() {
    string filename = active_filename();
    Program program = Program.find_containing(filename);

    string working_directory = program.get_top_directory();
    string command = program.config_file.get_clean_command();
    spawn_process(command, working_directory, on_clean_finished);
}

////////////////////////////////////////////////////////////
//           Menu activation and plugin class             //
////////////////////////////////////////////////////////////

    bool errors_exist() {
        Program program = get_active_document_program();
        return program.error_list != null && program.error_list.errors.size != 0;
    }

    bool program_exists_for_active_document() {
        string filename = active_filename();
        return filename != null && Program.find_existing(filename) != null;
    }

    void on_search_menu_activated() {
        bool document_is_vala_file = active_document_is_vala_file();
        go_to_definition_menu_item.set_sensitive(document_is_vala_file);
        find_symbol_menu_item.set_sensitive(document_is_vala_file);
        go_to_outer_scope_menu_item.set_sensitive(document_is_vala_file);
        
        go_back_menu_item.set_sensitive(can_go_back());
        go_forward_menu_item.set_sensitive(can_go_forward());

        bool activate_error_search = active_filename() != null && 
                                     program_exists_for_active_document() && errors_exist();

        next_error_menu_item.set_sensitive(activate_error_search);
        prev_error_menu_item.set_sensitive(activate_error_search);
        
        display_tooltip_menu_item.set_sensitive(document_is_vala_file);
    }

    void on_project_menu_activated() {
        bool active_file_not_null = active_filename() != null;
        build_menu_item.set_sensitive(active_file_not_null);
        clean_menu_item.set_sensitive(active_file_not_null);

        // Make sure the program for the file exists first, otherwise disable the run button        
        if (active_file_not_null && program_exists_for_active_document()) {
            Program program = get_active_document_program();
            program.reparse_makefile();
            string binary_path = program.get_binary_run_path();
            
            run_menu_item.set_sensitive(!child_process_running && binary_path != null &&
                                        program.get_binary_is_executable());
        } else {
            run_menu_item.set_sensitive(false);
        }

        settings_menu_item.set_sensitive(active_file_not_null);
    }

    public void update_state() {
    }

    public void deactivate() {
        Gtk.UIManager manager = window.get_ui_manager();
        manager.remove_ui(ui_id);
        manager.remove_action_group(action_group);

        Gedit.Panel panel = window.get_bottom_panel();
        panel.remove_item(output_pane);
        panel.remove_item(run_pane);
        
        symbol_browser.deactivate();
        
        SignalHandler.disconnect(window, symbol_browser_connect_id);
        instances.remove(this);
    }
}

[ModuleInit]
public void peas_register_types (TypeModule module) {
	var o = module as Peas.ObjectModule;
 	o.register_extension_type(typeof(Gedit.WindowActivatable), typeof(Instance));
}
