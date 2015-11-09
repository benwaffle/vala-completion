/* ast.vala
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
	public class CodeDom
	{
		public Vala.HashMap<string, unowned Symbol> symbols = new Vala.HashMap <string, unowned Symbol>(GLib.str_hash, GLib.str_equal);
		public Vala.List<unowned Symbol> unresolved_symbols = new Vala.ArrayList<unowned Symbol>();
		
		private Symbol _root = new Symbol (null, MemberType.NONE);

		~CodeDom ()
		{
			Utils.trace ("CodeDom destroy");
			// destroy the root symbol
			if (has_source_files) {
				foreach (SourceFile file in source_files) {
					file.codedom = null;
				}
			}
			_root = null;
			source_files = null;// source have to be destroyed after root symbol
			Utils.trace ("CodeDom destroyed");
		}

		public void dump_symbols ()
		{
			foreach (var s in symbols.get_values ()) {
				Utils.trace ("%s (%p)", s.fully_qualified_name, s);
			}
		}

		public Symbol root {
			get { return _root; }
			set { _root = value; }
		}

		public Vala.List<SourceFile> source_files { get; set; }
	
		internal Symbol? lookup (string fully_qualified_name)
		{
			Symbol result = null;

			foreach (var s in symbols.get_values ()) {
				if (s is GLib.Object) {
					if (s.fully_qualified_name == fully_qualified_name) {
						result = s;
						break;
					}
				} else {
					critical ("FIXME: destroyed object in symbol table: %p", s);
				}
			}
			return result;
		}
		
		private static Symbol? lookup_symbol (string qualified_name, Symbol parent_symbol, 
			ref Symbol? parent,  CompareMode mode,
			SymbolAccessibility access = SymbolAccessibility.ANY, MemberBinding binding = MemberBinding.ANY)
		{
			string[] tmp = qualified_name.split (".", 2);
			string name = tmp[0];
		
			if (!parent_symbol.has_children)
				return null;

			foreach (Symbol symbol in parent_symbol.children) {
				//Utils.trace ("  Looking for %s: %s in %s", qualified_name, name, symbol.fully_qualified_name);
				
				if (compare_symbol_names (symbol.name, name, mode)
				    && (symbol.access & access) != 0
				    && (symbol.binding & binding) != 0) {
					if (tmp.length > 1) {
						Symbol child_sym = null;

						parent = symbol;
						if (symbol.has_children) {
							child_sym = lookup_symbol (tmp[1], symbol, ref parent, mode, access, binding);
						}

						return child_sym;
					} else {
						return symbol;
					}
				}
			}

			return null;
		}

		public bool has_source_files
		{
			get {
				return source_files != null;
			}
		}

		internal SourceFile add_source_file (string filename)
		{
			var file = lookup_source_file (filename);
			if (file == null) {
				file = new SourceFile (filename);
				if (source_files == null) {
					source_files = new ArrayList<SourceFile> ();
				}
				//Utils.trace ("add source: %s (%p)", file.filename, file);
				file.codedom = this;
				source_files.add (file);
			}
			return file;
		}
		
		public SourceFile? lookup_source_file (string filename)
		{
			if (source_files != null) {
				/*
				foreach (SourceFile file in source_files) {
					Utils.trace ("dumping sources %s: %d", file.filename, file.has_symbols ? file.symbols.size : 0);
				}
				Utils.trace ("dump end");
				*/

				foreach (SourceFile file in source_files) {
					if (file.filename == filename) {
						return file;
					}
				}
			}
			return null;
		}
		
		internal void remove_source (SourceFile source)
		{
			return_if_fail (source_files != null);
			if (source.has_symbols) {
				foreach (Afrodite.Symbol symbol in source.symbols) {
					if (symbol.has_source_references && symbol.source_references.size == 1) {
						source.remove_symbol_from_codedom (symbol);
					}
				}
			}
			source_files.remove (source);
		}
		
		public Symbol? lookup_symbol_at (string filename, int line, int column)
		{
			var source = lookup_source_file (filename);
			if (source == null || !source.has_symbols)
				return null;
			
			Symbol sym = get_symbol_for_source_and_position (source, line, column);
			return sym;
		}

		public QueryResult get_symbol_for_name_and_path (QueryOptions options, 
			string symbol_qualified_name, string path, int line, int column)
		{
			var result = new Afrodite.QueryResult ();
			var symbol = get_symbol_or_type_for_name_and_path (LookupMode.Symbol, options.binding, options, symbol_qualified_name, path, line, column);
			if (symbol != null) {
				var item = result.new_result_item (null, symbol);
				result.add_result_item (item);
			}
			return result;
		}
	
		public QueryResult get_symbol_type_for_name_and_path (QueryOptions options, 
			string symbol_qualified_name, string path, int line, int column)
		{
			var result = new Afrodite.QueryResult ();
			var symbol = get_symbol_or_type_for_name_and_path (LookupMode.Type, options.binding, options, symbol_qualified_name, path, line, column);
			if (symbol != null) {
				var item = result.new_result_item (null, symbol);
				result.add_result_item (item);
			}
			return result;
		}

		private Symbol? get_symbol_or_type_for_name_and_path (LookupMode mode, MemberBinding binding, QueryOptions options, string symbol_qualified_name, string path, int line, int column)
		{
			var source = lookup_source_file (path);
			if (source == null || !source.has_symbols) {
				warning ("source file %s %s without any symbols", path, source == null ? "not found, so" : "found but");
				return null;
			}
			
			Symbol sym = get_symbol_for_source_and_position (source, line, column);
			if (sym != null) {
				string[] parts = symbol_qualified_name.split (".");
				// change the scope of symbol search
				if (options.auto_member_binding_mode) {
					if (parts[0] == "this") {
						//Utils.trace ("CHANGE REMOVE STATIC");
						binding = binding & (~ ((int) MemberBinding.STATIC));
						options.binding = binding;
						options.access = options.access | SymbolAccessibility.PRIVATE;
					} else if (parts[0] == "base") {
						//Utils.trace ("CHANGE REMOVE STATIC & PRIVATE");
						binding = binding & (~ ((int) MemberBinding.STATIC));
						options.binding = binding;
						options.access = options.access 
							& (~ ((int) SymbolAccessibility.PRIVATE)) 
							| SymbolAccessibility.PROTECTED;
					}
				}

				sym = lookup_name_with_symbol (parts[0], sym, source, options.compare_mode);
				if (sym != null && sym.symbol_type != null) {
					if (mode != LookupMode.Symbol || parts.length > 1) {
						sym = sym.symbol_type.symbol;
					}
				}
				
				if (parts.length > 1 && sym != null && sym.has_children) {
					if (sym.member_type == MemberType.NAMESPACE
					    || (parts[0] == sym.name 
					        && (sym.member_type == MemberType.CLASS || sym.member_type == MemberType.STRUCT || sym.member_type == MemberType.INTERFACE))) {
					    	// namespace access or MyClass.my_static_method
						//debug ("CHANGE ONLY STATIC");
						binding = MemberBinding.STATIC;
					}
					for (int i = 1; i < parts.length; i++) {
	 					Symbol parent = sym;
	 					Symbol dummy = null;
	 					
	 					//print ("lookup %s in %s", parts[i], sym.name);
						sym = lookup_symbol (parts[i], sym, ref dummy, options.compare_mode);
						if (sym == null) {
							// lookup on base types also
							sym = lookup_name_in_base_types (parts[i], parent);
						}
						
						//print ("... result: %s\n", sym == null ? "not found" : sym.name);
						if (sym != null && mode == LookupMode.Type && sym.symbol_type != null) {
							//debug ("result type %s", sym.symbol_type.unresolved ? "<unresolved>" : sym.symbol_type.symbol.name);
							
							sym = sym.symbol_type.symbol;
						} else {
							break;
						}
					}
				}
			}
			
			// return the symbol or the return type: for properties, field and methods
			if (sym != null && sym.symbol_type != null && mode == LookupMode.Type)
				return sym.symbol_type.symbol;
			else
				return sym;
		}
				
		public QueryResult get_symbols_for_path (QueryOptions options, string path)
		{
			var result = new QueryResult ();
			var first = result.new_result_item (null, _root);
			//var timer = new Timer ();
			
			//timer.start ();
			get_child_symbols_for_path (result, options, path, first);
			if (first.children.size > 0) {
				result.add_result_item (first);
			}
			//timer.stop ();
			//debug ("get_symbols_for_path simbols found %d, time elapsed %g", result.children.size, timer.elapsed ());
			return result;
		}

		private void get_child_symbols_for_path (QueryResult result, QueryOptions? options, string path, ResultItem parent)
		{
			if (!parent.symbol.has_children)
				return;

			foreach (Symbol symbol in parent.symbol.children) {
				if (symbol_has_filename_reference(path, symbol)) {
					if (symbol.check_options (options)) {
						var result_item = result.new_result_item (parent, symbol);
						parent.add_result_item (result_item);
						if (symbol.has_children) {
							// try to catch circular references
							var item = parent.symbol;
							bool circular_ref = false;
					
							while (item != null) {
								if (symbol == item) {
									critical ("circular reference %s", symbol.fully_qualified_name);
									circular_ref = true;
									break;
								}
								item = item.parent;
							}
							// find in children
							if (!circular_ref) {
								get_child_symbols_for_path (result, options, path, result_item);
							}
						}
					}
				}
			}
		}
		
		private bool symbol_has_filename_reference (string filename, Symbol symbol)
		{
			if (!symbol.has_source_references)
				return false;

			foreach (SourceReference sr in symbol.source_references) {
				if (sr.file.filename == filename) {
					return true;
				}
			}
			
			return false;
		}
		private Symbol? lookup_name_in_base_types (string name, Symbol? symbol,
			SymbolAccessibility access = SymbolAccessibility.ANY, MemberBinding binding = MemberBinding.ANY)
		{
			// search in base classes / interfaces
			if (symbol.has_base_types) {
				Symbol parent = null;
				foreach (DataType type in symbol.base_types) {
					if (!type.unresolved) {
						if (type.symbol.name == name
						    && (type.symbol.access & access) != 0
						    && (type.symbol.binding & binding) != 0) {
							return type.symbol;
						}
						if (type.symbol.has_children) {
							var sym = lookup_symbol (name, type.symbol, ref parent, CompareMode.EXACT, access, binding);
							if (sym != null) {
								return sym;
							}
						}
					}
				}
					
			}
			
			return null;
		}
		
		private Symbol? lookup_this_symbol (Symbol? root)
		{
			// search first class in the parent chain, break when a namespace is found
			Symbol current = root;
			while (current != null) {
				if (current.member_type == MemberType.CLASS || current.member_type == MemberType.STRUCT) {
					break;
				} else if (current.member_type == MemberType.NAMESPACE) {
					current = null; // exit
				} else
					current = current.parent;
			}

			return current;
		}
		
		private void append_visible_symbols (Vala.List<Afrodite.Symbol>? results, 
			Symbol symbol,
			string? name, 
			CompareMode mode, 
			CaseSensitiveness case_sensitiveness,
			SymbolAccessibility access = SymbolAccessibility.ANY)
		{
			//Utils.trace ("scanning symbol: %s", symbol.fully_qualified_name);
			if (symbol.has_local_variables) {
				foreach (DataType d in symbol.local_variables) {
					if (!d.unresolved 
					    && ((access & SymbolAccessibility.PRIVATE) != 0)
					    && (name == null || compare_symbol_names (d.name, name, mode, case_sensitiveness))) {
						var s = new Afrodite.Symbol (d.name, MemberType.LOCAL_VARIABLE);
						s.return_type = d.copy ();
						s.return_type.symbol = d.symbol;
						results.add (s);
					}
				}
			}
			
			if (symbol.has_parameters) {
				// symbol parameters (eg. method parameters)
				foreach (DataType d in symbol.parameters) {
					if (!d.unresolved 
					    && ((access & SymbolAccessibility.PRIVATE) != 0)
					    && (name == null || compare_symbol_names (d.name, name, mode, case_sensitiveness))) {
						var s = new Afrodite.Symbol (d.name, MemberType.PARAMETER);
						s.return_type = d.copy ();
						s.return_type.symbol = d.symbol;
						results.add (s);
					}

				}
			}
			
			if (symbol.has_children) {
				// direct children
				foreach (Symbol s in symbol.children) {
					if ((s.access & access) != 0
					    && (s.fully_qualified_name != symbol.fully_qualified_name)
					    && (name == null || compare_symbol_names (s.name, name, mode, case_sensitiveness))) {
						results.add (s);
					}
				}
			}
			
			if (symbol.has_base_types) {
				foreach (DataType d in symbol.base_types) {
					if (!d.unresolved) {
						append_visible_symbols  (results, 
							d.symbol, 
							name, 
							mode,
							case_sensitiveness,
							SymbolAccessibility.INTERNAL | SymbolAccessibility.PROTECTED | SymbolAccessibility.PUBLIC);
					}
				}
			}
		}

		private void append_all_visible_symbols (Vala.List<Afrodite.Symbol> results, 
			Afrodite.Symbol? symbol, 
			string? name, 
			CompareMode mode, 
			CaseSensitiveness case_sensitiveness)
		{
			append_visible_symbols (results, symbol, name, mode, case_sensitiveness);

			if (symbol.parent != null) {
				append_all_visible_symbols (results, symbol.parent, name, mode, case_sensitiveness);
			}
		}
		
		public Vala.List<Afrodite.Symbol> lookup_visible_symbols_from_symbol (Afrodite.Symbol symbol, 
			string? name = null,
			CompareMode mode = CompareMode.START_WITH, 
			CaseSensitiveness case_sensitiveness = CaseSensitiveness.CASE_SENSITIVE)
		{
			Vala.List<Afrodite.Symbol> results = new Vala.ArrayList<Afrodite.Symbol> ();
			append_all_visible_symbols (results, symbol, name, mode, case_sensitiveness);
			
			// append symbols from the imported namespaces
			if (symbol.has_source_references) {
				var using_done = new Vala.ArrayList<string> ();
			
				foreach (SourceReference s in symbol.source_references) {
					if (s.file.has_using_directives) {
						Utils.trace ("import symbol from symbol %s, file: %s", symbol.fully_qualified_name,  s.file.filename);
						foreach (var u in s.file.using_directives) {
							if (!using_done.contains (u.type_name)) {
								using_done.add (u.type_name);
								Utils.trace ("    import symbol from namespace: %s", u.type_name);
								if (!u.unresolved)
									append_visible_symbols (results, 
										u.symbol, 
										name, 
										mode, 
										case_sensitiveness, 
										SymbolAccessibility.INTERNAL | SymbolAccessibility.PUBLIC);
							}
						}
					}
				}
			}

			return results;
		}
		
		private static bool compare_symbol_names (string? name1, string? name2, CompareMode mode, CaseSensitiveness case_sensitiveness = CaseSensitiveness.CASE_SENSITIVE)
		{
			string a = name1;
			string b = name2;
			
			switch (case_sensitiveness) {
				case CaseSensitiveness.CASE_INSENSITIVE:
					a = name1 != null ? name1.down () : null;
					b = name2 != null ? name2.down () : null;
					break;
				case CaseSensitiveness.AUTO:
					if (name2.down () == name2) {
						a = name1 != null ? name1.down () : null;
						b = name2 != null ? name2.down () : null;
					}
					break;
			}
			//Utils.trace ("comparing: %s vs %s %d %d", a, b, (int)mode, (int) case_sensitiveness);
			
			if (mode == CompareMode.START_WITH) {
				if (a != null && b != null)
					return a.has_prefix (b);
				else
					return false;
			} else {
				return a == b;
			}
		}

		private Symbol? lookup_name_with_symbol (string name, Symbol? symbol, SourceFile source, CompareMode mode,
			SymbolAccessibility access = SymbolAccessibility.ANY, MemberBinding binding = MemberBinding.ANY)
		{
			// first try to find the symbol datatype
			if (name == "this") {
				return lookup_this_symbol (symbol);
			} else if (name == "base") {
				Symbol? this_sym = lookup_this_symbol (symbol);
				
				if (this_sym != null && this_sym.has_base_types) {
					foreach (DataType type in this_sym.base_types) {
						//debug ("search base types: %s", type.type_name);
						
						if (!type.unresolved && type.symbol.member_type == MemberType.CLASS) {
							return type.symbol;
						}
					}
				}
			} else {
				// search in local vars going up in the scope chain
				var current_sym = symbol;
				while (current_sym != null) {
					if (current_sym.has_local_variables) {
						foreach (DataType type in current_sym.local_variables) {
							if (!type.unresolved) {
								if (compare_symbol_names (type.name, name, mode)
								    && (type.symbol.access & access) != 0
								    && (type.symbol.binding & binding) != 0) {
									return type.symbol;
								}
							}
						}
					}
					// search in symbol parameters
					if (current_sym.has_parameters) {
						foreach (DataType type in current_sym.parameters) {
							if (!type.unresolved) {
								if (compare_symbol_names (type.name, name, mode)
								    && (type.symbol.access & access) != 0
								    && (type.symbol.binding & binding) != 0) {
									return type.symbol;
								}
							}
						}
					}
					current_sym = current_sym.parent;
				}

				// search in sibling
				current_sym = symbol.parent;
				while (current_sym != null) {
					if (current_sym != null && current_sym.has_children) {
						foreach (Symbol sibling in current_sym.children) {
							if (sibling != symbol && compare_symbol_names (sibling.name, name, mode)
							    && (sibling.access & access) != 0
							    && (sibling.binding & binding) != 0) {
								return sibling;
							}
						}
					}
					current_sym = current_sym.parent;
				}
								
				var sym = lookup_name_in_base_types (name, symbol, access, binding);
				if (sym != null)
					return sym;
					
				// search in using directives
				if (source.has_using_directives) {
					foreach (DataType u in source.using_directives) {
						
						
						sym = lookup (u.type_name);
						if (sym != null) {
							Symbol parent = sym.parent;
							if (compare_symbol_names (sym.name, name, mode)) {
								// is a reference to a namespace
								return sym;
							} else if (sym.has_children) {
								sym = lookup_symbol (name, sym, ref parent, mode, access, binding);
								if (sym != null) {
									return sym;
								}
							}
						}
					}
				}

			}
			return null;
		}

		public Symbol? get_symbol_for_source_and_position (SourceFile source, int line, int column)
		{
			Symbol result = null;
			unowned SourceReference result_sr = null;
			
			if (source.has_symbols) {
				// base 0
				line++;
				foreach (Symbol symbol in source.symbols) {
					var sr = symbol.lookup_source_reference_sourcefile (source);
					if (sr == null) {
						// symbols imported by dependencies don't have any source associated with it
						// critical ("symbol %s doesn't belong to source %s", symbol.fully_qualified_name, source.filename);
						continue;
					}
					//Utils.trace ("searching %s: %d-%d %d-%d vs %d, %d", symbol.name, sr.first_line, sr.first_column, sr.last_line, sr.last_column, line, column);
					if (sr.contains_position (line, column)) {
						// let's find the best symbol
						if (result == null || result_sr.contains_source_reference (sr)) {
							// this symbol is better
							result = symbol;
							result_sr = sr;
						}
					}
				}
			}
			
			if (result == null) {
				Utils.trace ("no symbol found");
			} else {
				Utils.trace ("   found %s", result.fully_qualified_name);
			}
			
			return result;
		}
	}
}
