/* sourcefile.vala
 *
 * Copyright (C) 2009  Andrea Del Signore
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 * 	Andrea Del Signore <sejerpz@tin.it>
 */

using GLib;
using Vala;

namespace Afrodite
{
	public class SourceFile
	{
		private string _filename;

		public Vala.List<DataType> using_directives { get; set; }
		public Vala.List<unowned Symbol> symbols { get; set; }
		public unowned CodeDom codedom { get; set; }

		public TimeVal last_modification_time;
		
		public string filename {
			get {
				return _filename;
			}
			set {
				_filename = value;
				update_last_modification_time ();
			}
		}
		
		public SourceFile (string filename)
		{
			this.filename = filename;
		}

		public bool update_last_modification_time ()
		{
			TimeVal new_value;
			bool result = true;

			try {
				var info = File.new_for_path (_filename).query_info (FileAttribute.TIME_MODIFIED + "," + FileAttribute.TIME_MODIFIED_USEC, FileQueryInfoFlags.NONE);
				new_value = info.get_modification_time ( );
				result = !(last_modification_time.tv_sec == new_value.tv_sec
					   && last_modification_time.tv_usec == new_value.tv_usec);
				last_modification_time = new_value;
			} catch (Error err) {
				critical ("error while updating last modification time: %s", err.message);
			}
			return result;
		}

		~SourceFile ()
		{
			Utils.trace ("SourceFile destroying: %s", filename);
			while (symbols != null && symbols.size > 0) {
				var symbol = symbols.get (0);
				remove_symbol (symbol);
			}
			Utils.trace ("SourceFile destroyed: %s", filename);
			
		}

		public DataType add_using_directive (string name)
		{
			var u = lookup_using_directive (name);
			if (u == null) {
				if (using_directives == null) {
					using_directives = new ArrayList<DataType> ();
				}
				u = new DataType (name, "UsingDirective");
				using_directives.add (u);
			}
			return u;
		}
		
		public DataType? lookup_using_directive (string name)
		{
			if (using_directives != null) {
				foreach (DataType u in using_directives) {
					if (u.type_name == name) {
						return u;
					}
				}
			}
			
			return null;
		}
		
		public void remove_using_directive (string name)
		{
			var u = lookup_using_directive (name);
			if (u != null) {
				using_directives.remove (u);
				if (using_directives.size == 0)
					using_directives = null;
			}
		}
		
		public bool has_using_directives
		{
			get {
				return using_directives != null;
			}
		}
		
		public void add_symbol (Symbol symbol)
		{
			if (symbols == null) {
				symbols = new ArrayList<unowned Symbol> ();
			}

			symbols.add (symbol);

			codedom.symbols.set (symbol.fully_qualified_name, symbol);

			codedom.unresolved_symbols.add(symbol);
		}

		public void remove_symbol (Symbol symbol)
		{
			var sr = symbol.lookup_source_reference_sourcefile (this);
			assert (sr != null);

			//Utils.trace ("%s removing symbol %s: %u", filename, symbol.fully_qualified_name, symbol.ref_count);
			symbol.remove_source_reference (sr);
			//this is done by remove_source_reference: symbols.remove (symbol);
			if (symbols.size == 0)
				symbols = null;

			if (!symbol.has_source_references) {
				if (codedom != null) {
					remove_symbol_from_codedom (symbol);
				}
				if (symbol.parent != null) {
					if (symbol.is_generic_type_argument) {
						symbol.parent.remove_generic_type_argument (symbol);
					} else if (symbol.parent.has_children) {
						symbol.parent.remove_child (symbol);
					}
				}
				if (symbol.generic_parent != null && symbol.generic_parent.has_specialized_symbols) {
					symbol.generic_parent.remove_specialized_symbol (symbol);
				}
			}

			//Utils.trace ("%s removed symbol %s: %u", filename, symbol.fully_qualified_name, symbol.ref_count);
		}
		
		public bool has_symbols
		{
			get {
				return symbols != null;
			}
		}
		
		internal void remove_symbol_from_codedom (Symbol symbol)
		{
			//Utils.trace ("%s removing from ast: %s", filename, symbol.fully_qualified_name);
			if (codedom != null && codedom.symbols != null) {
				codedom.symbols.remove (symbol.fully_qualified_name);
			}
			if (codedom != null && codedom.unresolved_symbols != null) {
				codedom.unresolved_symbols.remove (symbol);
			}
		}
	}
}
