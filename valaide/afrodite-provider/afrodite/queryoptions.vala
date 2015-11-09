/* queryoptions.vala
 *
 * Copyright (C) 2010 Andrea Del Signore
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
	public class QueryOptions
	{
		public bool all_symbols = false; // don't filter
		public bool only_creation_methods = false;
		public bool only_static_factories = false; // this covers static methods factories and struct initialization
		public bool only_error_domains = false;
		public bool exclude_creation_methods = true;
		public bool exclude_code_node = true; // skip code node: symbols that starts with ! and rapresent a statement with scope like if or foreach
		
		public SymbolAccessibility access = SymbolAccessibility.ANY;
		
		public bool auto_member_binding_mode = true; // if true the query function will adapt the member binding value automatically
		public MemberBinding binding = MemberBinding.ANY;

		public CompareMode compare_mode = CompareMode.EXACT;
		
		public static QueryOptions standard ()
		{
			return new QueryOptions ();
		}
		
		public static QueryOptions creation_methods ()
		{
			var opt = new QueryOptions ();
			opt.only_creation_methods = true;
			opt.exclude_creation_methods = false;
			return opt;
		}
		
		public static QueryOptions factory_methods ()
		{
			var opt = new QueryOptions ();
			opt.only_static_factories = true;
			return opt;
		}
		
		public static QueryOptions error_domains ()
		{
			var opt = new QueryOptions ();
			opt.only_error_domains = true;
			return opt;
		}
		
		public void dump_settings ()
		{
			Utils.trace ("Member Binding (autoadapt: %s)", auto_member_binding_mode ? "true" : "false");
			Utils.trace ("    Instance: %s", (binding & MemberBinding.INSTANCE) != 0 ? "true" : "false");
			Utils.trace ("    Static: %s", (binding & MemberBinding.STATIC) != 0 ? "true" : "false");
			Utils.trace ("    Class: %s", (binding & MemberBinding.CLASS) != 0 ? "true" : "false");

			Utils.trace ("Scope");
			Utils.trace ("    Private: %s", (access & SymbolAccessibility.PRIVATE) != 0 ? "true" : "false");
			Utils.trace ("    Protected: %s", (access & SymbolAccessibility.PROTECTED) != 0 ? "true" : "false");
			Utils.trace ("    Internal: %s", (access & SymbolAccessibility.INTERNAL) != 0 ? "true" : "false");
			Utils.trace ("    Public: %s", (access & SymbolAccessibility.PUBLIC) != 0 ? "true" : "false");
			
			Utils.trace ("All symbols.............: %s", all_symbols ? "true" : "false");
			Utils.trace ("Error domains only......: %s", only_error_domains ? "true" : "false");
			Utils.trace ("Static factories only...: %s", only_static_factories ? "true" : "false");
			Utils.trace ("Creation methods only...: %s", only_creation_methods ? "true" : "false");
			Utils.trace ("Creation methods exclude: %s", exclude_creation_methods ? "true" : "false");
		}
	}
}
