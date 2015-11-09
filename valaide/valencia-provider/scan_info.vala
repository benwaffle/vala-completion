/* scan_info.vala
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
 * 	Nicolas Joseph <nicolas.joseph@valaide.org>
 */

class Valencia.ScanInfo : Object
{
  public int cursor_pos;
  public Method? method;
  public ParseInfo parse_info;

  private Gtk.TextBuffer buffer;
    
  private static Gtk.TextIter get_insert_iter (Gtk.TextBuffer buffer)
  {
    Gtk.TextIter iter;

    buffer.get_iter_at_mark(out iter, buffer.get_insert());
    return iter;
  }

  private static unowned string buffer_contents (Gtk.TextBuffer buffer)
  {
    Gtk.TextIter end;
    Gtk.TextIter start;

    buffer.get_bounds (out start, out end);
    return buffer.get_text (start, end, true);
  }

  private static void get_buffer_str_and_pos (Gtk.TextBuffer buffer,
                                              out unowned string source,
                                              out int pos)
  {
    Gtk.TextIter insert;

    //this.reparse_modified_documents (buffer.path);
    source = buffer_contents (buffer);
    insert = get_insert_iter (buffer);
    pos = insert.get_offset();
  }

  public ScanInfo.empty ()
  {
  }

  public Expression inner ()
  {
    return parse_info.inner;
  }

  public Expression outer ()
  {
    return parse_info.outer;
  }

  public ScanInfo(Method? method, ParseInfo parse_info, int cursor_position) {
    this.method = method;
    this.parse_info = parse_info;
    cursor_pos = cursor_position;
  }

  public static Valencia.ScanInfo? get_scan_info (Valide.SourceBuffer buffer,
                                                  bool partial)
  {
    int cursor_pos;
    string filename;
    Valencia.Method? method;
    Valencia.ParseInfo parse_info;

    unowned string source;
    get_buffer_str_and_pos (buffer, out source, out cursor_pos);

    filename = buffer.path;
    parse_info = new Valencia.ExpressionParser (source, cursor_pos, partial).parse ();

    Valencia.Program program = Valencia.Program.find_containing (filename);
    Valencia.SourceFile sf = program.find_source(filename);
    // The sourcefile may be null if the file is a vala file but hasn't been saved to disk
    if (sf == null)
      return null;

    // Give the method tooltip precedence over autocomplete
    method = null;
    if (parse_info.outer != null) {
      Valencia.Symbol? sym = sf.resolve (parse_info.outer, cursor_pos, false);
      if (sym != null)
        method = sym as Valencia.Method;
    }

    return new Valencia.ScanInfo (method, parse_info, cursor_pos);
  }
}

