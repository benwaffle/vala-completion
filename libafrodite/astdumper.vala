/* contextdump.vala
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
	public class AstDumper : CodeVisitor
	{
		string pad = null;
		int level = 0;
		int symbols = 0;
		int unresolved_types = 0;
		int types = 0;
				
		private void inc_pad ()
		{
			if (pad == null) {
				pad = "";
				level = 0;
			} else {
				level++;
				pad = string.nfill (level, '\t');
			}
		}
		
		private void dec_pad ()
		{
			if (pad == null) {
				pad = "";
				level = 0;
				GLib.error ("dec_pad call!!!");
			} else if (level == 0) {
				pad = null;
			} else {
				level--;
				pad = string.nfill (level, '\t');
			}
		}
		
		private void print_symbol (Afrodite.Symbol? s)
		{
			print ("%s\n", create_symbol_dump_info (s));
		}

		internal string create_symbol_dump_info (Afrodite.Symbol? s, bool update_counters = true)
		{
			if (s == null)
				return "(empty)";
			
			if (pad == null)
				inc_pad ();
				
			var sb = new StringBuilder ();
			
			sb.append (pad);

			if (s.member_type == MemberType.NAMESPACE
			    || s.member_type == MemberType.CLASS
			    || s.member_type == MemberType.STRUCT
			    || s.member_type == MemberType.INTERFACE
			    || s.member_type == MemberType.ENUM
			    || s.member_type == MemberType.ERROR_DOMAIN)
				sb.append_printf ("%s ", Utils.Symbols.get_symbol_type_description (s.member_type));

			sb.append_printf ("%s ", Utils.unescape_xml_string (s.description));
			
			if (s.has_source_references) {
				sb.append ("   - [");
				foreach (SourceReference sr in s.source_references) {
					sb.append_printf ("(%d - %d) %s, ", sr.first_line, sr.last_line, sr.file.filename);
				}
				sb.truncate (sb.len - 2);
				sb.append ("]");
			}
			if (update_counters)
				symbols++;
			return sb.str;
		}

		public void dump (CodeDom ast, string? filter_symbol = null)
		{
			pad = null;
			level = 0;
			symbols = 0;
			unresolved_types = 0;
			types = 0;

			var timer = new Timer ();
			timer.start ();

			if (ast.root.has_children) {
				dump_symbols (ast.root.children, filter_symbol);
				print ("Dump done. Symbols %d, Types examinated %d of which unresolved %d\n\n", symbols, types, unresolved_types);
			} else
				print ("context empty!\n");

			if (ast.has_source_files) {
				print ("Source files:\n");
				foreach (SourceFile file in ast.source_files) {
					print ("\tsource: %s\n", file.filename);
					if (file.has_using_directives) {
						print ("\t\tusing directives:\n");
						foreach (DataType d in file.using_directives) {
							print ("\t\t\tusing: %s\n", d.type_name);
						}
					}
				}
			}
			timer.stop ();
			print ("Dump done in %g\n", timer.elapsed ());
		}

		private void dump_symbols (Vala.List<Afrodite.Symbol> symbols, string? filter_symbol)
		{
			inc_pad ();
			foreach (Symbol symbol in symbols) {
				if (filter_symbol == "" || filter_symbol == null || filter_symbol == symbol.fully_qualified_name) {
					print_symbol (symbol);
					if (symbol.has_local_variables) {
						inc_pad ();
						print ("%slocal variables\n", pad);
						foreach (DataType local in symbol.local_variables) {
							unowned SourceReference sr = local.source_reference;
							print ("%s   %s     - [(%d - %d) %s]\n",
								pad,
								Utils.unescape_xml_string (local.description),
								sr.first_line,
								sr.last_line,
								sr.file.filename);
							
						}
						dec_pad ();
					}
					if (symbol.has_children) {
						dump_symbols (symbol.children, null);
					}
				}
			}
			dec_pad ();
		}
	}
}
