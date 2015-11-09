/* completion.vala
 *
 * Copyright (C) 2008-2010 Nicolas Joseph
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

public class Completion : Plugin, Object
{
  private uint ui_id;
  private Gtk.ActionGroup action_group = null;

  const Gtk.ActionEntry[] entries = {
    { "search-goto-definition", null, "Go to Definition", "<ctrl>D",
      "Goto the definition of the current symbol", on_goto_definition }
  };

  const string ui = """
      <ui>
        <menubar name="menubar">
          <menu action="search">
            <placeholder name="search-ops-3">
              <menuitem action="search-goto-definition"/>
            </placeholder>
          </menu>
        </menubar>
      </ui>""";

  /**
   * @see Valide.Plugin.path
   */
  public string path { get; construct set; }
  /**
   * @see Valide.Plugin.window
   */
  public Window window { get; construct set; }

  private void on_goto_definition ()
  {
    AfroditeProvider provider = new AfroditeProvider (this.window.documents.current);
    Afrodite.Symbol? item = provider.get_current_symbol_item (500);

    if (item != null)
    {
      if (item.has_source_references)
      {
        try
        {
          int col;
          int line;
          string uri;
          Document document;

          uri = Filename.to_uri (item.source_references.get(0).file.filename);
          line = item.source_references.get(0).first_line;
          col = item.source_references.get(0).first_column;

          document = this.window.documents.create (uri);
          document.view.goto_line (line, col);
        } catch (Error e) {
          warning ("error %s converting file %s to uri", e.message, item.source_references.get(0).file.filename);
        }
      }
    } else {
      //display_completion_lock_failed_message ();
    }
  }

  private void setup_ui (DocumentManager sender, Document? document)
  {
    bool active = false;

    if (this.action_group == null)
    {
      Gtk.UIManager ui_manager;

      ui_manager = this.window.ui_manager;
      this.action_group = new Gtk.ActionGroup ("completion");
      this.action_group.add_actions (this.entries, this);
      ui_manager.insert_action_group (this.action_group, 0);
      try
      {
        this.ui_id = ui_manager.add_ui_from_string (ui, -1);
      }
      catch (Error e)
      {
        debug (e.message);
      }
    }

    if (sender.current != null)
    {
      active = true;
    }
    this.action_group.get_action ("search-goto-definition").sensitive = active;
  }

  private void on_tab_added (DocumentManager sender, Document document)
  {
    try
    {
      string filename;
      Gtk.SourceView source_view;
      Gtk.SourceCompletion completion;

      filename = document.path;
      source_view = document.split_view.active_view;
      completion = source_view.get_completion ();
      //completion.show_headers = false;
      completion.remember_info_visibility = true;
      completion.select_on_show = true;

      completion.add_provider ((Gtk.SourceCompletionProvider)new AfroditeProvider (document));

      this.setup_ui (this.window.documents, null);
    }
    catch (Error e)
    {
      debug (e.message);
    }
  }

  construct
  {
    this.window.documents.tab_added.connect (this.on_tab_added);
    this.window.documents.tab_removed.connect (this.setup_ui);
    this.setup_ui (this.window.documents, null);
  }

  ~Completion ()
  {
    this.window.documents.tab_added.disconnect (this.on_tab_added);
    this.window.documents.tab_removed.disconnect (this.setup_ui);

    this.window.ui_manager.remove_ui (this.ui_id);
  }
}

public Type register_plugin (TypeModule module)
{
  return typeof (Completion);
}
