/* datatype.vala
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

namespace Afrodite
{
	public class DataType
	{		
		public unowned Symbol? symbol { get; set; }
			
		public string name { get; set; }
		public bool is_array { get; set; }
		public bool is_pointer { get; set; }
		public bool is_generic { get; set; }
		public bool is_nullable { get; set; }
		public bool is_out { get; set; }
		public bool is_ref { get; set; }
		public bool is_dynamic { get; set; }
		public bool is_ellipsis { get; set; }
		public bool is_iterator { get; set; }
		public string default_expression { get; set; }
		public Vala.List<DataType> generic_types { get; set; }
		public SourceReference source_reference { get; set; }
		
		private string _type_name = null;
		
		public DataType (string type_name, string? name = null)
		{
			this.name = name;
			this.type_name = type_name;
		}

		public string type_name
		{
			get {
				return _type_name;
			}
			set {
				_type_name = process_type_name (fix_simple_type_name (value));
			}
		}

		public bool unresolved
		{
			get {
				return type_name != null && symbol == null;
			}
		}

		private string fix_simple_type_name (string type_name)
		{
			// HACK: this should fix bogus binary inferred type eg. int.float.double.int etc
			string[] types = type_name.split (".");
			
			if (types.length > 1) {
				string result = null;
				foreach (string type in types) {
					if (type != "int" && type != "float" && type != "double") {
						// type not known giving up
						return type_name;
					}
				
					if (result == null) {
						result = type;
					} else if (result != type) {
						if (result == "int" && (type == "float" || type == "double")) {
							result = type;
						}
					}
				}
				return result;
			} else {
				return type_name;
			}
			
		}
		
		private string process_type_name (string type_name)
		{
			var sb = new StringBuilder ();
			int skip_level = 0; // skip_level == 0 --> add char, skip_level > 0 --> skip until closed par (,[,<,{ causes a skip until ),],>,}
			//print ("process type_name %s %s\n",name, type_name);
			
			for (int i = 0; i < type_name.length; i++) {
				unichar ch = type_name[i];
				
				if (skip_level > 0) {
					if (ch == ']' || ch == '>')
						skip_level--;
					
					continue;
				}
				
				if (ch == '*') {
					is_pointer = true;
				} else if (ch == '?') {
					is_nullable = true;
				} else if (ch == '!') {
					is_nullable = false; // very old vala syntax!!!
				} else if (ch == '[') {
					is_array = true;
					skip_level++;
				} else if (ch == '<') {
					is_generic = true;
					skip_level++;
				} else
					sb.append_unichar (ch);
			}
			return sb.str;
		}
		
		public bool has_generic_types
		{
			get {
				return generic_types != null;
			}
		}
		
		public void add_generic_type (DataType type)
		{
			if (generic_types == null) {
				generic_types = new Vala.ArrayList<DataType>();
			}
			generic_types.add (type);
		}
		
		public void remove_generic_type (DataType type)
		{
			generic_types.remove (type);
			if (generic_types.size == 0) {
				generic_types = null;
			}
		}
		
		public string description
		{
			owned get {
				string res;
				
				if (is_ellipsis) {
					res = "...";
				} else {
					if (is_out)
						res = "out ";
					else if (is_ref)
						res = "ref ";
					else
						res = "";
					
					if (is_dynamic)
						res += "dynamic ";
					
					if (symbol == null)
						res += "%s!".printf (type_name);
					else
						res += symbol.fully_qualified_name ;
						
					if (is_pointer)
						res += "*";
					if (is_array)
						res += "[]";
					if (this.has_generic_types) {
						var sb = new StringBuilder ();
						sb.append ("&lt;");
						foreach (DataType t in generic_types) {
							sb.append_printf ("%s, ", t.description);
						}
						sb.truncate (sb.len - 2);
						sb.append ("&gt;");
						res += sb.str;
					}
					if (is_nullable)
						res += "?";
				
					if (name != null && name != "") {
						res += " %s".printf (name);
					}
					if (default_expression != null && default_expression != "") {
						res += " = " + default_expression;
					}
				}
				return res;
			}
		}

		public DataType copy ()
		{
			var res = new DataType (type_name, name);
			res._type_name = type_name;
			res.name = name;
			res.symbol = null;
			res.is_array = is_array;
			res.is_pointer = is_pointer;
			res.is_generic = is_generic;
			res.is_nullable = is_nullable;
			res.is_out = is_out;
			res.is_ref = is_ref;
			res.is_dynamic = is_dynamic;
			res.is_ellipsis = is_ellipsis;
			res.is_iterator = is_iterator;
			res.default_expression = default_expression;
			if (generic_types != null) {
				foreach (var item in generic_types) {
					res.add_generic_type (item.copy ());
				}
			}
			res.source_reference = source_reference;
			return res;
		}
	}
}
