/* valencia-provider.vala
 *
 * Copyright (C) 2010 Nicolas Joseph
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

class ValenciaProvider : Fix.SourceCompletionProvider, Object
{
  private Gtk.SourceCompletionContext context;

  public SourceBuffer buffer { get; construct; }

  private Gdk.Pixbuf valencia_type_to_icon (Valencia.Symbol symbol)
  {
    string type;
    string valencia_type;

    valencia_type = symbol.get_type ().name ();
    type = valencia_type.substring ("Valencia".len ()).down ();
    return Valide.Utils.get_symbol_pixbuf (type);
  }

  string strip_completed_classnames(string list_name, string completion_target) {
    string[] classnames = completion_target.split(".");
    int names = classnames.length;
    // If the last classname is not explicitly part of the class qualification, then it 
    // should not be removed from the completion suggestion's name
    if (!completion_target.has_suffix("."))
        --names;
        
    for (int i = 0; i < names; ++i) {
      unowned string name = classnames[i];

      // If the name doesn't contain the current classname, it may be a namespace name that
      // isn't part of the list_name string - we shouldn't stop the comparison early
      if (list_name.contains(name)) {
        // Add one to the offset of a string to account for the "."
        long offset = name.length;
        if (offset > 0)
            ++offset;
        list_name = list_name.offset(offset);
      }
    }

    return list_name;
  }

  private string parse_single_symbol(Valencia.Symbol symbol,
                                     string? completion_target,
                                     bool constructor) {
    string list_name = "";
    
    if (constructor) {
      // Get the fully-qualified constructor name
      Valencia.Constructor c = symbol as Valencia.Constructor;
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
      if (symbol is Valencia.Method
          && !(symbol is Valencia.VSignal)
          && !(symbol is Valencia.Delegate))
        list_name = symbol.name + "()";
    }
    
    return list_name;
  }

  private unowned string? get_completion_target() {
    Gtk.TextIter end;
    Gtk.TextIter start;

    this.buffer.get_iter_at_mark (out start, buffer.get_insert());
    this.buffer.get_iter_at_mark (out end, buffer.get_insert());
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

  private void on_parse_end ()
  {
    Valencia.ScanInfo? info;

    info = Valencia.ScanInfo.get_scan_info (this.buffer, true);
    if (info != null)
    {
      /* popup */
      Valencia.Expression e;
      Valencia.SourceFile sf;
      Valencia.Program program;
      Valencia.SymbolSet symbol_set;
      Vala.HashSet<Valencia.Symbol>? symbols;
      List<Gtk.SourceCompletionItem> items;

      e = info.inner ();
      if (e == null)
      {
        if (info.method != null)
        {
          return;
        }
        e = new Valencia.Id ("");
      }

      program = Valencia.Program.find_containing (this.buffer.path);
      sf = program.find_source (this.buffer.path);
      symbol_set = sf.resolve_prefix (e, info.cursor_pos, false);
      symbols = symbol_set.get_symbols ();
      if (symbols != null)
      {
        bool constructor;
        string? symbol_string;
        string? symbol_info = null;
        string? completion_target = null;

        items = new List <Gtk.SourceCompletionItem> ();
        foreach (Valencia.Symbol s in symbols)
        {
          constructor = (s is Valencia.Constructor);

          if (constructor)
          {
            completion_target = this.get_completion_target();
          }
          else
          {
            completion_target = null;
          }

          if (s is Valencia.Method)
          {
            symbol_info = (s as Valencia.Method).to_string ();
          }
          else
          {
            symbol_info = null;
          }
          symbol_string = this.parse_single_symbol (s, completion_target, constructor);
          items.append (new Gtk.SourceCompletionItem (symbol_string, symbol_string,
                                                      this.valencia_type_to_icon (s),
                                                      symbol_info));
        }
        this.context.add_proposals (this, items, true);
      }
    }
  }

  public ValenciaProvider (Document document)
  {
    Object (buffer: document.buffer);
  }

  /**
   * @see Gtk.SourceCompletionProvider.activate_proposal
   */
  public bool activate_proposal (Gtk.SourceCompletionProposal proposal,
                                 Gtk.TextIter iter)
  {
    return false;
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_activation
   */
  public Gtk.SourceCompletionActivation get_activation ()
  {
    return Gtk.SourceCompletionActivation.USER_REQUESTED;
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_icon
   */
  public Gdk.Pixbuf get_icon ()
  {
    return null;
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_info_widget
   */
  public Gtk.Widget get_info_widget (Gtk.SourceCompletionProposal proposal)
  {
    return null;
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_interactive_delay
   */
  public int get_interactive_delay ()
  {
    return -1;
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_name
   */
  public string get_name ()
  {
    return _("Valencia");
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_priority
   */
  public int get_priority ()
  {
    return 0;
  }

  /**
   * @see Gtk.SourceCompletionProvider.get_start_iter
   */
  public bool get_start_iter (Gtk.SourceCompletionContext context,
                              Gtk.SourceCompletionProposal proposal,
                              Gtk.TextIter iter)
  {
    return false;
  }

  /**
   * @see Gtk.SourceCompletionProvider.match
   */
  public bool match (Gtk.SourceCompletionContext context)
  {
    return true;
  }

  /**
   * @see Gtk.SourceCompletionProvider.populate
   */
  public void populate (Gtk.SourceCompletionContext context)
  {
    Valencia.Program program;

    this.context = context;
    program = Valencia.Program.find_containing (this.buffer.path, true);
    if (program.is_parsing ())
    {
      program.system_parse_complete.connect (this.on_parse_end);
    }
    else
    {
      this.on_parse_end ();
    }
  }

  /**
   * @see Gtk.SourceCompletionProvider.update_info
   */
  public void update_info (Gtk.SourceCompletionProposal proposal, 
                           Gtk.SourceCompletionInfo info)
  {
  }
}

