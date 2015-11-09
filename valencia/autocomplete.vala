/* Copyright 2009-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Gee;
using Valencia;

class AutocompleteDialog : Object {
    weak Gedit.Window parent;
    Gtk.Window window;
    ListViewString list;
    bool visible;
    string partial_name;
    bool inserting_text;

    public AutocompleteDialog(Gedit.Window parent_win) {
        parent = parent_win;
        visible = false;
        inserting_text = false;
        list = new ListViewString(Gtk.TreeViewColumnSizing.AUTOSIZE, 100);
        list.row_activated.connect(select_item);

        window = new Gtk.Window(Gtk.WindowType.POPUP); 
        window.add(list.scrolled_window);
        window.set_destroy_with_parent(true);
        window.set_default_size(200, 1); 
        window.set_resizable(true);
        window.set_title("");
        window.set_border_width(1);
      
        window.show_all();
        window.hide();
    }

    string? get_completion_target(Gtk.TextBuffer buffer) {
        Gtk.TextIter start = get_insert_iter(buffer);
        Gtk.TextIter end = start;
        
        while (true) {
            start.backward_char();
            unichar c = start.get_char();
            if (!c.isalnum() && c != '.' && c != '_')
                break;
        }
        // Only include characters in the ID name
        start.forward_char();
        
        if (start.get_offset() == end.get_offset())
            return null;
        
        return start.get_slice(end);
    }
    
    string strip_completed_classnames(string list_name, string completion_target) {
        string result = list_name;
        
        string[] classnames = completion_target.split(".");
        int names = classnames.length;
        // If the last classname is not explicitly part of the class qualification, then it 
        // should not be removed from the completion suggestion's name
        if (!completion_target.has_suffix("."))
            --names;
            
        for (int i = 0; i < names; ++i) {
            weak string name = classnames[i];

            // If the name doesn't contain the current classname, it may be a namespace name that
            // isn't part of the list_name string - we shouldn't stop the comparison early
            if (result.contains(name)) {
                // Add one to the offset of a string to account for the "."
                long offset = name.length;
                if (offset > 0)
                    ++offset;
                result = result.substring(offset);
            }
        }

        return result;
    }

    string parse_single_symbol(Symbol symbol, string? completion_target, bool constructor) {
        string list_name = "";
        
        if (constructor) {
            // Get the fully-qualified constructor name
            Constructor c = symbol as Constructor;
            assert(c != null);

            list_name = c.parent.to_string();
            
            if (c.name != null)
                list_name += "." + c.name;
            list_name += "()";

            // If the user hasn't typed anything or if either the completion string or this 
            // constructor is not qualified, keep the original name
            if (completion_target != null && completion_target.contains(".") 
                && list_name.contains("."))
                list_name = strip_completed_classnames(list_name, completion_target);
            
        } else {
            list_name = symbol.name;
            if (symbol is Method && !(symbol is VSignal) && !(symbol is Delegate))
                list_name = symbol.name + "()";
        }
        
        return list_name;
    }

    string[]? parse_symbol_names(HashSet<Symbol>? symbols) {
        if (symbols == null)
            return null;
            
        string[] list = new string[symbols.size];

        // If the first element is a constructor, all elements will be constructors
        Iterator<Symbol> iter = symbols.iterator();
        iter.next();
        bool constructor = iter.get() is Constructor;

        // match the extent of what the user has already typed with named constructors
        string? completion_target = null;
        if (constructor) {          
            completion_target = get_completion_target(parent.get_active_document());
        }

        int i = 0;
        foreach (Symbol symbol in symbols) {
            list[i] = parse_single_symbol(symbol, completion_target, constructor);
            ++i;
        }
            
        qsort(list, symbols.size, sizeof(string), (GLib.CompareFunc) compare_string);
        return list;
    }

    public void show(SymbolSet symbol_set) {
        if (inserting_text)
            return;

        list.clear();
        visible = true;
        partial_name = symbol_set.get_name();

       weak HashSet<Symbol>? symbols = symbol_set.get_symbols();
       string[]? symbol_strings = parse_symbol_names(symbols);

        if (symbol_strings != null) {
            foreach (string s in symbol_strings) {
                list.append(s);
            }
        } else {
            hide();
            return;
        }

        // TODO: this must be updated to account for font size changes when adding ticket #560        
        int size = list.size();
        if (size > 6) {
            list.set_vscrollbar_policy(Gtk.PolicyType.AUTOMATIC);
            window.resize(200, 140);
        } else {
            list.set_vscrollbar_policy(Gtk.PolicyType.NEVER);
            window.resize(200, size * 23);
        }

        Gedit.Document document = parent.get_active_document(); 
        Gtk.TextMark insert_mark = document.get_insert();
        Gtk.TextIter insert_iter;
        document.get_iter_at_mark(out insert_iter, insert_mark); 
        int x, y;
        get_coords_at_buffer_offset(parent, insert_iter.get_offset(), false, true, out x, out y);

        window.move(x, y);
        window.show_all(); 
        window.queue_draw();
        select_first_cell();
    }
    
    public void hide() {
        if (!visible)
            return;
        
        visible = false;
        window.hide();
    }

    public bool is_visible() {
        return visible;
    }

    public void select_first_cell() {
        list.select_first_cell();
    }

    public void select_last_cell() {
        list.select_last_cell();
    }

    public void select_previous() {
        list.select_previous();
    }

    public void select_next() {
        list.select_next();
    }

    public void page_up() {
        list.page_up();
    }

    public void page_down() {
        list.page_down();
    }

    public void select_item() {
        string selection = list.get_selected_item();
        Gedit.Document buffer = parent.get_active_document();

        // delete the whole string to be autocompleted and replace it (the case may not match)
        Gtk.TextIter start = get_insert_iter(buffer);
        while (true) {
            if (!start.backward_char())
                break;
            unichar c = start.get_char();
            if (!c.isalnum() && c != '_')
                break;
        }
        // don't include the nonalphanumeric character
        start.forward_char();

        Gtk.TextIter end = start;
        while (true) {
            unichar c = end.get_char();
            if (c == '(') {
                end.forward_char();
                break;
            }
            if (!c.isalnum() && c != '_' && c != '.')
                break;
            if (!end.forward_char())
                break;
        }

        // Text insertion/deletion signals have been linked to updating the autocomplete dialog -
        // we don't want to do that if we're already inserting text.
        inserting_text = true;
        buffer.delete(ref start, ref end);

        long offset = selection.has_suffix(")") ? 1 : 0;
        buffer.insert_at_cursor(selection, (int) (selection.length - offset));
        inserting_text = false;

        hide();
    }
}

