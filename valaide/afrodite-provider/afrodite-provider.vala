/* afrodite-provider.vala
 *
 * Copyright (C) 2010-2011 Nicolas Joseph
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 *   Nicolas Joseph <nicolas.joseph@valaide.org>
 */

using Valide;

internal class AfroditeProvider : Fix.SourceCompletionProvider, Object
{
  public signal void completion_lock_failed ();

  private Gdk.Pixbuf icon;
  private int priority = 1;
  private List<Gtk.SourceCompletionItem> proposals;

  private Afrodite.SourceItem sb = null;

  private uint timeout_id = 0;
  private uint idle_id = 0;
  private bool all_doc = false; //this is a hack!!!

  private int prealloc_index = 0;

  private bool cache_building = false;
  private bool filter = false;
  //private uint sb_msg_id = 0;
  //private uint sb_context_id = 0;

  private Gtk.SourceCompletionInfo calltip_window = null;
  private Gtk.Label calltip_window_label = null;

  private int last_line = -1;
  private bool doc_changed = false;

  private Afrodite.CompletionEngine completion = null;

  public unowned Document document
  {
    get;
    construct;
  }

  public AfroditeProvider (Document document)
  {
    Object (document: document);
  }

  construct
  {
    this.icon = this.get_icon ();

    string name = Vtg.Utils.get_document_name (this.document.buffer);

    this.sb = new Afrodite.SourceItem ();
    this.sb.path = name;
    this.sb.content = this.document.buffer.get_buffer_contents ();

    this.document.view.key_press_event.connect (this.on_view_key_press);
    this.document.view.focus_out_event.connect (this.on_view_focus_out);
    this.document.view.get_completion ().show.connect (this.on_completion_window_hide);

    this.document.buffer.notify["text"] += this.on_text_changed;
    this.document.buffer.notify["cursor-position"] += this.on_cursor_position_changed;
    Signal.connect (this.document, "saved", (Callback)on_document_saved, this);

    //var status_bar = (Gedit.Statusbar) _symbol_completion.plugin_instance.window.get_statusbar ();
    //sb_context_id = status_bar.get_context_id ("symbol status");

    this.cache_building = true;
    this.all_doc = true;
    //_symbol_completion.notify["completion-engine"].connect (this.on_completion_engine_changed);
    this.completion = new Afrodite.CompletionEngine ("Afrodite");
  }

  ~SymbolCompletionProvider ()
  {
    if (this.timeout_id != 0)
    {
      GLib.Source.remove (this.timeout_id);
    }
    if (this.idle_id != 0)
    {
      GLib.Source.remove (this.idle_id);
    }

    this.document.view.key_press_event.disconnect (this.on_view_key_press);
    this.document.view.focus_out_event.disconnect (this.on_view_focus_out);

    SourceBuffer doc = this.document.buffer;
    //_symbol_completion.notify["completion-engine"].disconnect (this.on_completion_engine_changed);
    doc.notify["text"] -= this.on_text_changed;
    doc.notify["cursor-position"] -= this.on_cursor_position_changed;
    SignalHandler.disconnect_by_func (doc, (void*)this.on_document_saved, this);
/*
    if (this.sb_msg_id != 0)
    {
      var status_bar = (Gedit.Statusbar) _symbol_completion.plugin_instance.window.get_statusbar ();
      status_bar.remove (_sb_context_id, _sb_msg_id);
    }
*/
  }

  public string get_name ()
  {
    return _("Afrodite");
  }

  public int get_priority ()
  {
    return this.priority;
  }

  public bool match (Gtk.SourceCompletionContext context)
  {
    SourceBuffer src = this.document.buffer;
    unowned Gtk.TextMark mark = src.get_insert ();
    Gtk.TextIter start;

    src.get_iter_at_mark (out start, mark);
    Gtk.TextIter pos = start;
    bool result = !Vtg.Utils.is_inside_comment_or_literal (src, pos);

    if (result)
    {
      pos = start;
      int line = pos.get_line ();
      unichar ch = pos.get_char ();
      if (pos.backward_char ())
      {
        if (pos.get_line () == line)
        {
          unichar prev_ch = pos.get_char ();
          if (prev_ch == '(' || ch == '('
              || prev_ch == '[' || ch == '['
              || prev_ch == ' '
              || prev_ch == ')'
              || prev_ch == ']'
              || prev_ch == ';'
              || prev_ch == '?'
              || prev_ch == '/' || ch == '/'
              || prev_ch == ',')
          {
            result = false;
            Vtg.Utils.trace ("not match current char: '%s', previous: '%s'", ch.to_string (), prev_ch.to_string ());
          }
          else
          {
            Vtg.Utils.trace ("match current char: '%s', previous: '%s'", ch.to_string (), prev_ch.to_string ());
          }
        }
      }
    }

    return result;
  }

  private void on_completion_window_hide (Gtk.SourceCompletion sender)
  {
    this.filter = false;
  }

  public void populate (Gtk.SourceCompletionContext context)
  {
    Vtg.Utils.trace ("populate");
    unowned Gtk.TextMark mark = (Gtk.TextMark) context.completion.view.get_buffer ().get_insert ();
    Gtk.TextIter start;
    Gtk.TextIter end;
    context.completion.view.get_buffer ().get_iter_at_mark (out start, mark);
    context.completion.view.get_buffer ().get_iter_at_mark (out end, mark);

    if (!start.starts_line ())
    {
      start.set_line_offset (0);
    }

    string text = start.get_text (end);
    unichar prev_ch = 'a';
    if (end.backward_char ())
    {
      prev_ch = end.get_char ();
      end.forward_char ();
    }

    bool symbols_in_scope_mode = false;
    string word = "";
    this.filter = true;

    if (text.has_suffix (".") || (prev_ch != '_' && !prev_ch.isalnum()))
    {
      this.filter = false;
    }
    else
    {
      bool dummy, is_declaration;
      Vtg.ParserUtils.parse_line (text, out word, out dummy, out dummy, out is_declaration);

      if (!is_declaration && word.last_index_of (".") != -1)
      {
        symbols_in_scope_mode = true;
        this.filter = false;
      }
    }

    if (!this.filter)
    {
      this.proposals = new List<Gtk.SourceCompletionItem> ();
      if (symbols_in_scope_mode)
      {
        this.lookup_visible_symbols_in_scope (word, Afrodite.CompareMode.START_WITH);
      }
      else
      {
        this.complete_current_word ();
      }

      context.add_proposals ((Gtk.SourceCompletionProvider)this, this.proposals, true);
    }
    else
    {
      string[] tmp = word.split (".");
      string last_part = "";

      if (tmp.length > 0)
      {
        last_part = tmp[tmp.length-1];
      }

      Vtg.Utils.trace ("filtering with: '%s' - '%s'", word, last_part);
      if (!Vtg.StringUtils.is_null_or_empty (last_part))
      {
        List<Gtk.SourceCompletionItem> filtered_proposals = new List<Gtk.SourceCompletionItem> ();
        foreach (Gtk.SourceCompletionItem proposal in this.proposals)
        {
          if (proposal.get_label ().has_prefix (last_part))
          {
            filtered_proposals.append (proposal);
          }
        }

        if (this.proposals.length () > 0 && filtered_proposals.length () == 0) {
          // no matching add a dummy one to prevent proposal windows from closing
          Gtk.SourceCompletionItem dummy_proposal = new Gtk.SourceCompletionItem (_("No matching proposal"), "", null, null);
          filtered_proposals.append (dummy_proposal);
        }
        context.add_proposals ((Gtk.SourceCompletionProvider)this, filtered_proposals, true);
      }
      else
      {
        // match all optimization
        context.add_proposals ((Gtk.SourceCompletionProvider)this, this.proposals, true);
      }
    }
  }

  public Gdk.Pixbuf get_icon ()
  {
    if (this.icon == null)
    {
      try
      {
        Gtk.IconTheme theme = Gtk.IconTheme.get_default ();
        this.icon = theme.load_icon (Gtk.Stock.DIALOG_INFO, 16, 0);
      }
      catch (Error err)
      {
        critical ("error: %s", err.message);
      }
    }
    return this.icon;
  }

  public bool activate_proposal (Gtk.SourceCompletionProposal proposal, Gtk.TextIter iter)
  {
    this.filter = false;
    return false;
  }

  public Gtk.SourceCompletionActivation get_activation ()
  {
    return Gtk.SourceCompletionActivation.INTERACTIVE |
      Gtk.SourceCompletionActivation.USER_REQUESTED;
  }

  public Gtk.Widget get_info_widget (Gtk.SourceCompletionProposal proposal)
  {
    return null;
  }

  public int get_interactive_delay ()
  {
    return 10;
  }

  public bool get_start_iter (Gtk.SourceCompletionContext context, Gtk.SourceCompletionProposal proposal, Gtk.TextIter iter)
  {
    return false;
  }

  public void update_info (Gtk.SourceCompletionProposal proposal, Gtk.SourceCompletionInfo info)
  {
  }

  private bool on_view_focus_out (Gtk.Widget sender, Gdk.EventFocus event)
  {
    this.hide_calltip ();
    return false;
  }

  [CCode(instance_pos=-1)]
  private void on_document_saved (Document doc)
  {
    this.doc_changed = true;
    this.all_doc = true;
    this.schedule_reparse ();
  }
/*
  private void on_completion_engine_changed (Object sender, ParamSpec pspec)
  {
    this.completion = this.document.completion_engine;
  }
*/
  private int get_current_line_index (SourceBuffer? doc = null)
  {
    if (doc == null)
    {
      doc = this.document.view.source_buffer;
    }

    // get current line
    unowned Gtk.TextMark mark = doc.get_insert ();
    Gtk.TextIter start;
    doc.get_iter_at_mark (out start, mark);
    return start.get_line ();
  }

  private void schedule_reparse ()
  {
    if (this.timeout_id == 0 && this.doc_changed)
    {
      this.timeout_id = Timeout.add (250, this.on_timeout_parse);
    }
  }

  private void on_text_changed (Object sender, ParamSpec pspec)
  {
    this.doc_changed = true;
    // parse text only on init or line changes
    if (this.last_line == -1 || this.last_line != this.get_current_line_index ())
    {
      this.all_doc = true;
      this.schedule_reparse ();
    }
  }

  private void on_cursor_position_changed (Object sender, ParamSpec pspec)
  {
    // parse text only on init or line changes
    if (this.last_line == -1 || this.last_line != this.get_current_line_index ())
    {
      this.all_doc = true;
      this.schedule_reparse ();
    }
  }

  private bool on_timeout_parse ()
  {
    SourceBuffer doc = this.document.buffer;
    this.parse (this.document);
    this.timeout_id = 0;
    this.last_line = this.get_current_line_index (doc);
    return false;
  }

  private bool on_view_key_press (Gtk.Widget sender, Gdk.EventKey evt)
  {
    unichar ch = Gdk.keyval_to_unicode (evt.keyval);

    if (ch == '(')
    {
      this.show_calltip ();
    }
    else if (evt.keyval == Gdk.KeySyms.Escape || ch == ')' || ch == ';' || ch == '{' ||
        (evt.keyval == Gdk.KeySyms.Return && (evt.state & Gdk.ModifierType.SHIFT_MASK) != 0))
    {
      this.hide_calltip ();
    }
    if (evt.keyval == Gdk.KeySyms.Return || ch == ';')
    {
      this.all_doc = true; // new line or eol, reparse all source buffer
    }
    else if (ch.isprint ()
         || evt.keyval == Gdk.KeySyms.Delete
         || evt.keyval == Gdk.KeySyms.BackSpace)
    {
      this.all_doc = false; // a change so reparse the buffer minus the current line
      this.doc_changed = true;
    }
    return false;
  }

  private void show_calltip ()
  {
    Afrodite.Symbol? completion_result = this.get_current_symbol_item ();
    if (completion_result != null)
    {
      this.show_calltip_info (completion_result.info);
    }
  }

  private void show_calltip_info (string markup_text)
  {
    if (this.calltip_window == null)
    {
      this.initialize_calltip_window ();
    }

    if (markup_text != null)
    {
      this.calltip_window_label.set_markup (markup_text);
      this.calltip_window.move_to_iter (this.document.view);
      this.calltip_window.show_all ();
      this.calltip_window.show ();
    }
  }

  private void hide_calltip ()
  {
    if (this.calltip_window == null)
    {
      return;
    }

    this.calltip_window.hide ();
  }

  private void initialize_calltip_window ()
  {
    this.calltip_window = new Gtk.SourceCompletionInfo ();
    //this.calltip_window.set_transient_for (_symbol_completion.plugin_instance.window);
    this.calltip_window.set_sizing (800, 400, true, true);
    this.calltip_window_label = new Gtk.Label ("");
    this.calltip_window.set_widget (this.calltip_window_label);
  }

  private void parse (Document doc)
  {
    // automatically add package if this buffer
    // belong to the default project
/*
    var current_project = _symbol_completion.plugin_instance.project_view.current_project;
    if (current_project.is_default) {
      if (this.autoadd_packages (doc, current_project) > 0)
      {
        current_project.project.update ();
      }
    }
*/
    // schedule a parse
    var buffer = this.get_document_text (doc.buffer, this.all_doc);
    this.sb.content = buffer;
    this.completion.queue_source (this.sb);
    this.doc_changed = false;
  }
/*
  private int autoadd_packages (Gedit.Document doc, Vtg.ProjectManager project_manager)
  {

    int added_count = 0;

    try {
      var text = this.get_document_text (doc, true);
      GLib.Regex regex = new GLib.Regex ("""^\s*(using)\s+(\w\S*)\s*;.*$""");

      foreach (string line in text.split ("\n")) {
        GLib.MatchInfo match;
        regex.match (line, RegexMatchFlags.NEWLINE_ANY, out match);
        while (match.matches ()) {
          string using_name = null;

          if (match.fetch (2) == "GLib") {
            // standard GLib are already merged by the completion engine
            // I'll add gio for the default project
            if (project_manager.is_default) {
              using_name = "gio";
            }
          } else {
            using_name = match.fetch (2);
          }
          string package_name = null;

          if (using_name != null)
            package_name = Vbf.Vtg.Utils.guess_package_name (using_name);

          Vtg.Utils.trace ("guessing name of using clause %s for package %s: %s", match.fetch (2), using_name, package_name);
          if (package_name != null) {
            var group = project_manager.project.get_group("Sources");
            var target = group.get_target_for_id ("Default");
            if (!target.contains_package (package_name))
            {
              target.add_package (new Vbf.Package (package_name));
              added_count++;
            }
          }
          match.next ();
        }
      }
    } catch (Error err) {
      critical ("error: %s", err.message);
    }

    return added_count;
  }
*/
  private bool proposal_list_contains_name (string name)
  {
    foreach (Gtk.SourceCompletionItem proposal in this.proposals)
    {
      if (proposal.get_label () == name)
      {
        return true;
      }
    }

    return false;
  }

  private void append_symbols (Afrodite.QueryOptions? options, Vala.List<Afrodite.Symbol> symbols, bool include_private_symbols = true)
  {
    unowned Gtk.SourceCompletionItem[] proposals = Vtg.Utils.get_proposal_cache ();

    foreach (Afrodite.Symbol symbol in symbols)
    {
      if ((!include_private_symbols && symbol.access == Afrodite.SymbolAccessibility.PRIVATE)
        || symbol.name == "new"
        || (options != null && !symbol.check_options (options)))
      {
        //Vtg.Utils.trace ("not append symbols: %s", symbol.name);
        continue;
      }

      string name;

      if (symbol.type_name == "CreationMethod")
      {
        name = symbol.name;
      }
      else
      {
        name = (symbol.display_name != null ? symbol.display_name : "<null>");
      }

      if (!symbol.overrides || (symbol.overrides && !this.proposal_list_contains_name (name)))
      {
        Gtk.SourceCompletionItem proposal;
        string info = (symbol.info != null ? symbol.info : "");
        Gdk.Pixbuf icon = Vtg.Utils.get_icon_for_type_name (symbol.type_name);

        if (this.prealloc_index < Vtg.Utils.prealloc_count)
        {
          proposal = proposals [this.prealloc_index];
          this.prealloc_index++;

          proposal.label = name;
          proposal.text = name;
          proposal.info = info;
          proposal.icon = icon;
        }
        else
        {
          proposal = new Gtk.SourceCompletionItem (name, name, icon, info);
        }
        //Vtg.Utils.trace ("append symbols: %s", symbol.name);
        this.proposals.append (proposal);
      }
    }
    //sort list
    this.proposals.sort (this.proposal_sort);
  }

  private static int proposal_sort (Gtk.SourceCompletionItem a,
                                    Gtk.SourceCompletionItem b)
  {
    return strcmp (a.get_label (), b.get_label ());
  }

  private void transform_result (Afrodite.QueryOptions? options, Afrodite.QueryResult? result)
  {
    this.prealloc_index = 0;
    this.proposals = new List<Gtk.SourceCompletionItem> ();
    Vala.ArrayList<Afrodite.Symbol> visited_interfaces = new Vala.ArrayList<Afrodite.Symbol> ();

    if (result != null && !result.is_empty)
    {
      options.dump_settings ();

      foreach (Afrodite.ResultItem item in result.children)
      {
        var symbol = item.symbol;

        if (options == null || symbol.check_options (options))
        {
          if (symbol.has_children)
          {
            append_symbols (options, symbol.children);
          }

          append_base_type_symbols (options, symbol, visited_interfaces);
        }
      }
    }
  }

  private void append_base_type_symbols (Afrodite.QueryOptions? options, Afrodite.Symbol symbol, Vala.List<Afrodite.Symbol> visited_interfaces)
  {
    if (symbol.has_base_types
        && (symbol.type_name == "Class" || symbol.type_name == "Interface" || symbol.type_name == "Struct"))
    {
      foreach (Afrodite.DataType type in symbol.base_types)
      {
        Vtg.Utils.trace ("visiting base type: %s", type.type_name);
        if (!type.unresolved
            && type.symbol.has_children
            && (options == null || type.symbol.check_options (options))
            && (type.symbol.type_name == "Class" || type.symbol.type_name == "Interface" || type.symbol.type_name == "Struct"))
        {
          // symbols of base types (classes or interfaces)
          if (!visited_interfaces.contains (type.symbol))
          {
            visited_interfaces.add (type.symbol);
            append_symbols (options, type.symbol.children, false);
            append_base_type_symbols (options, type.symbol, visited_interfaces);
          }
        }
      }
    }
    else
    {
      Vtg.Utils.trace ("NO base type for %s-%s", symbol.name, symbol.type_name);
    }
  }

  private void get_current_line_and_column (out int line, out int column)
  {
    unowned SourceBuffer doc = this.document.buffer;
    unowned Gtk.TextMark mark = doc.get_insert ();
    Gtk.TextIter start;

    doc.get_iter_at_mark (out start, mark);
    line = start.get_line ();
    column = start.get_line_offset ();
  }

  private string get_current_line_text (bool align_to_right_word)
  {
    unowned SourceBuffer doc = this.document.buffer;
    unowned Gtk.TextMark mark = doc.get_insert ();
    Gtk.TextIter end;
    Gtk.TextIter start;
    unichar ch;

    doc.get_iter_at_mark (out start, mark);
    int line = start.get_line ();

    //go to the right word boundary
    ch = start.get_char ();
    while (ch.isalnum () || ch == '_')
    {
      start.forward_char ();
      int curr_line = start.get_line ();
      if (line != curr_line) //changed line?
      {
        start.backward_char ();
        break;
      }
      ch = start.get_char ();
    }

    end = start;
    start.set_line_offset (0);
    return start.get_text (end);
  }

  public Afrodite.Symbol? get_current_symbol_item (int retry_count = 0)
  {
    string text = this.get_current_line_text (true);
    string word;
    int line, col;
    bool is_assignment, is_creation, is_declaration;

    Vtg.ParserUtils.parse_line (text, out word, out is_assignment, out is_creation, out is_declaration);

    if (word == null || word == "")
    {
      return null;
    }

    this.get_current_line_and_column (out line, out col);

    string[] tmp = word.split (".");
    string last_part = tmp[tmp.length - 1];
    string symbol_name = last_part;

    //don't try to find method signature if is a: for, foreach, if, while etc...
    if (is_vala_keyword (symbol_name))
    {
      return null;
    }

    /*
      strip last type part.
      eg. for demos.demo.demo_method obtains
      demos.demo + demo_method
    */
    string first_part;
    if (word != last_part)
    {
      first_part = word.substring (0, word.length - last_part.length - 1);
    }
    else
    {
      first_part = word; // "this"; //HACK: this won't work for static methods
    }

    Afrodite.Ast ast = completion.ast;
    Afrodite.Symbol? symbol = null;
    Afrodite.QueryResult? result = null;
    Afrodite.QueryOptions options = this.get_options_for_line (text, is_assignment, is_creation);

    if (word == symbol_name)
    {
      result = this.get_symbol_for_name (options, ast, first_part, null,  line, col);
    }
    else
    {
      result = this.get_symbol_type_for_name (options, ast, first_part, null,  line, col);
    }

    if (result != null && !result.is_empty)
    {
      var first = result.children.get (0);
      if (word == symbol_name)
      {
        symbol = first.symbol;
      }
      else
      {
        symbol = this.get_symbol_for_name_in_children (symbol_name, first.symbol);
        if (symbol == null)
        {
          symbol =this.get_symbol_for_name_in_base_types (symbol_name, first.symbol);
        }
      }
    }
    return symbol;
  }

  private Afrodite.Symbol? get_symbol_for_name_in_children (string symbol_name, Afrodite.Symbol parent)
  {
    if (parent.has_children)
    {
      foreach (Afrodite.Symbol? symbol in parent.children)
      {
        if (symbol.name == symbol_name)
        {
          return symbol;
        }
      }
    }
    return null;
  }

  private Afrodite.Symbol? get_symbol_for_name_in_base_types (string symbol_name, Afrodite.Symbol parent)
  {
    if (parent.has_base_types)
    {
      foreach  (Afrodite.DataType t in parent.base_types)
      {
        if (t.symbol != null)
        {
          var base_symbol = this.get_symbol_for_name_in_children (symbol_name, t.symbol);
          if (base_symbol == null)
          {
            base_symbol = this.get_symbol_for_name_in_base_types (symbol_name, t.symbol);
          }

          if (base_symbol != null)
          {
            return base_symbol;
          }
        }
      }
    }
    return null;
  }

  private Afrodite.QueryOptions get_options_for_line (string line, bool is_assignment, bool is_creation)
  {
    Afrodite.QueryOptions options = null;

    if (is_creation)
    {
      options = Afrodite.QueryOptions.creation_methods ();
    }
    else if (is_assignment || (line != null && line.last_index_of (":") != -1))
    {
      options = Afrodite.QueryOptions.standard ();
      options.binding |= Afrodite.MemberBinding.STATIC;
    }
    else if (line != null
      && (line.index_of ("throws ") != -1 || line.index_of ("throw ") != -1))
    {
      options = Afrodite.QueryOptions.error_domains ();
    }
    if (options == null)
    {
      options = Afrodite.QueryOptions.standard ();
    }

    options.access = Afrodite.SymbolAccessibility.INTERNAL | Afrodite.SymbolAccessibility.PROTECTED | Afrodite.SymbolAccessibility.PUBLIC;
    options.auto_member_binding_mode = true;
    options.compare_mode = Afrodite.CompareMode.EXACT;
    //options.dump_settings ();
    return options;
  }

  private void complete_current_word ()
  {
    //string whole_line, word, last_part;
    //int line, column;

    //parse_current_line (false, out word, out last_part, out whole_line, out line, out column);
    string text = this.get_current_line_text (false);
    string word;

    bool is_assignment, is_creation, is_declaration;

    Vtg.ParserUtils.parse_line (text, out word, out is_assignment, out is_creation, out is_declaration);

    Afrodite.Ast ast = completion.ast;
    Vtg.Utils.trace ("completing word: '%s'", word);
    if (!Vtg.StringUtils.is_null_or_empty (word))
    {
      Afrodite.QueryOptions options = this.get_options_for_line (text, is_assignment, is_creation);
      Afrodite.QueryResult result = null;
      int line, col;

      this.get_current_line_and_column (out line, out col);

      if (word.has_prefix ("\"") && word.has_suffix ("\""))
      {
        word = "string";
      }
      else if (word.has_prefix ("\'") && word.has_suffix ("\'"))
      {
        word = "unichar";
      }
      result = this.get_symbol_type_for_name (options, ast, word, text, line, col);
      this.transform_result (options, result);
    }
    else
    {
      if (!Vtg.StringUtils.is_null_or_empty (word))
      {
        Vtg.Utils.trace ("build_proposal_item_list: couldn't acquire ast lock");
        this.show_calltip_info (_("<i>source symbol cache is still updating...</i>"));
        Timeout.add_seconds (2, this.on_hide_calltip_timeout);
        this.completion_lock_failed ();
      }
      this.transform_result (null, null);
    }
  }

  private void lookup_visible_symbols_in_scope (string word, Afrodite.CompareMode mode)
  {
    Afrodite.Ast ast = completion.ast;
    Vtg.Utils.trace ("lookup_all_symbols_in_scope: mode: %s word:'%s' ",
      mode == Afrodite.CompareMode.EXACT ? "exact" : "start-with",
      word);
    if (!Vtg.StringUtils.is_null_or_empty (word))
    {
      Vala.List<Afrodite.Symbol> results = new Vala.ArrayList<Afrodite.Symbol> ();

      weak SourceBuffer doc = this.document.buffer;
      var source = ast.lookup_source_file (Vtg.Utils.get_document_name (doc));
      if (source != null)
      {
        // get the source node at this position
        int line, column;
        get_current_line_and_column (out line, out column);

        var s = ast.get_symbol_for_source_and_position (source, line, column);
        if (s != null)
        {
          results = ast.lookup_visible_symbols_from_symbol (s, word, mode, Afrodite.CaseSensitiveness.CASE_SENSITIVE);
        }
      }

      if (results.size == 0)
      {
        Vtg.Utils.trace ("no symbol visible");
        this.transform_result (null, null);
      }
      else
      {
        this.proposals = new List<Gtk.SourceCompletionItem> ();
        append_symbols (null, results);
      }
    }
    else
    {
      if (!Vtg.StringUtils.is_null_or_empty (word))
      {
        Vtg.Utils.trace ("build_proposal_item_list: couldn't acquire ast lock");
        this.completion_lock_failed ();
      }
      this.transform_result (null, null);
    }
  }

  private bool on_hide_calltip_timeout ()
  {
    this.hide_calltip ();
    return false;
  }

  private Afrodite.QueryResult? get_symbol_type_for_name (Afrodite.QueryOptions options, Afrodite.Ast ast, string word, string? whole_line, int line, int column)
  {
    Afrodite.QueryResult result = null;
    result = ast.get_symbol_type_for_name_and_path (options, word, this.sb.path, line, column);
    Vtg.Utils.trace ("symbol matched %d", result.children.size);
    return result;
  }

  private Afrodite.QueryResult? get_symbol_for_name (Afrodite.QueryOptions options, Afrodite.Ast ast,string word, string? whole_line, int line, int column)
  {
    Afrodite.QueryResult result = null;
    result = ast.get_symbol_for_name_and_path (options, word, this.sb.path, line, column);

    return result;
  }

  private bool is_vala_keyword (string keyword)
  {
    return (keyword == "if"
      || keyword == "for"
      || keyword == "foreach"
      || keyword == "while"
      || keyword == "switch");
  }

  private string get_document_text (SourceBuffer doc, bool all_doc = false)
  {
    weak Gtk.TextMark mark = doc.get_insert ();
    Gtk.TextIter end;
    Gtk.TextIter start;

    doc.get_iter_at_mark (out start, mark);
    string doc_text;
    if (all_doc || doc.is_untouched ())
    {
      end = start;
      start.set_line_offset (0);
      while (start.backward_line ())
      {
      }

      while (end.forward_line ())
      {
      }

      doc_text = start.get_text (end);
    }
    else
    {
      end = start;
      end.set_line_offset (0);
      while (start.backward_line ())
      {
      }

      string text1 = start.get_text (end);
      string text2 = "";
      //trick: jump the current edited row (there
      //are a lot of probability that this row will
      //cause a parser error)
      if (end.forward_line ())
      {
        end.set_line_offset (0);
        start = end;
        while (end.forward_line ())
        {
        }

        text2 = start.get_text (end);
      }
      doc_text = "%s\n%s".printf (text1, text2);
    }

    return doc_text;
  }
}

