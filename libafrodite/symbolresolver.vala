/* symbolresolver.vala
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
	public class SymbolResolver
	{
		CodeDom _codedom = null;
		string _vala_symbol_fqn = null;
		
		/*
		private void print_symbol (Symbol s)
		{
			string message = "  %s: %s, fqn %s\n".printf (s.type_name, s.name,  s.fully_qualified_name);
			print (message);
		}
		*/
	
		public void resolve (CodeDom codedom)
		{
			_vala_symbol_fqn = null;
			this._codedom = codedom;

			// first resolve the using directives
			if (_codedom.has_source_files) {
				foreach (SourceFile file in _codedom.source_files) {
					if (file.has_using_directives) {
						foreach (DataType using_directive in file.using_directives) {
							//
							if (using_directive.unresolved) {
								using_directive.symbol = _codedom.lookup (using_directive.type_name);
								if (using_directive.unresolved)
									message ("file %s - can't resolve using directive: %s", file.filename, using_directive.type_name);
							}
						}
					}
				}
			}

			if (codedom.unresolved_symbols.size > 0) {
				Afrodite.Utils.trace ("(symbol resolver): symbols to resolve %d", codedom.unresolved_symbols.size);
				visit_symbols (codedom.unresolved_symbols);
				Afrodite.Utils.trace ("(symbol resolver): unresolved symbol after resolve process %d", codedom.unresolved_symbols.size);
#if DEBUG
				int count = codedom.unresolved_symbols.size > 5 ? 5 : codedom.unresolved_symbols.size;
				if (count > 0) {
					Afrodite.Utils.trace ("(symbol resolver): dumping first %d", count);
					for(int i=0; i < count; i++) {
						var symbol = codedom.unresolved_symbols.get(i);
						var sr = symbol.source_references.get(0);
						string cause = null;
					
						if (symbol.symbol_type != null && symbol.symbol_type.unresolved) {
							cause = "symbol_type: %s".printf (symbol.symbol_type.type_name);
						}

						if (cause == null) {
							if (symbol.has_parameters) {
								foreach (Afrodite.DataType type in symbol.parameters) {
									if (type.unresolved) {
										cause = "parameter: %s".printf (type.type_name);
										break;
									}

								}
							}
						}
						if (cause == null) {
							if (symbol.has_local_variables) {
								foreach (Afrodite.DataType type in symbol.local_variables) {
									if (type.unresolved) {
										cause = "variable: %s".printf (type.type_name);
										break;
									}

								}
							}							
						}
						if (cause == null) {
							if (symbol.has_base_types) {
								foreach (DataType type in symbol.base_types) {
									if (type.unresolved) {
										cause = "base_type: %s".printf (type.type_name);
										break;
									}
								}
							}
						}
					
						Afrodite.Utils.trace ("\tname: %s %s (%s, line %d)", symbol.fully_qualified_name, cause, sr.file.filename, sr.first_line);
					}
				}
#endif
			}

		}

		private Symbol? resolve_type (Symbol symbol, DataType type)
		{
			var res = resolve_type_name (symbol, type.type_name);

			// if not found and there is a "." may be is a fully qualified name, do a global lookup
			if (res == null && type.type_name.contains (".")) {
				//Utils.trace ("resolving with %s.%s".printf (using_directive.type_name, type.type_name));
				var s = _codedom.symbols.@get (type.type_name);
				if (s != null && s != symbol) {
					res = s;
				}
			}

			if (res != null) {
				if (type.has_generic_types) {
					if (res.has_generic_type_arguments
					   && type.generic_types.size == res.generic_type_arguments.size) {
						// test is a declaration of a specialized generic type
						bool need_specialization = false;
						for(int i = 0; i < type.generic_types.size; i++) {
							string name = res.generic_type_arguments[i].fully_qualified_name ?? res.generic_type_arguments[i].name;
							if (type.generic_types[i].type_name != name) {
								need_specialization = true;
								break;
							}
						}
						if (need_specialization) {
							//Utils.trace ("%s generic type %s resolved with type %s", symbol.fully_qualified_name, type.type_name, res.fully_qualified_name);
							res = specialize_generic_symbol (type, res);
						}
					} else {
						// resolve type generic types
						foreach (DataType generic_type in type.generic_types) {
							if (generic_type.unresolved)
								generic_type.symbol = resolve_type (res, generic_type);
						}
					}
				}

				if (res != Symbol.VOID) {
					res.add_resolved_target (symbol);
				}
			}

			return res;
		}

		private Symbol? resolve_type_name (Symbol symbol, string type_name)
		{
			//string[] parts = type_name.split(".");
			var current = symbol;
			
						// void symbol
			if (type_name == "void" || type_name == "...") {
				current = Symbol.VOID;
			} else {
				//Utils.trace ("START Resolving symbol %s type %s", current.name, type_name);
				/*
				
				*/
				
				// fast lookup first
				current = _codedom.symbols.@get (type_name);
				
				// if not found or I just found myself
				if (current == null || current == symbol) {
					string[] parts = type_name.split(".");
					current = symbol;
					foreach (string part in parts) {
						//Utils.trace ("\tresolving from %s: %s", current.name, part);
						current = resolve_type_name_part (current, part);
						if (current != null) {
							if (current.symbol_type != null) {
								if (current.symbol_type.unresolved)
									visit_symbol (current);

								current = current.symbol_type.symbol;
							}
						}
						if (current == null)
							break;
					}
				}

				if (current != null) {
					if (current.symbol_type != null) {
						if (current.symbol_type.unresolved)
							visit_symbol (current);

						current = current.symbol_type.symbol;
					}
				}
			}		
			//Utils.trace ("END  Resolving symbol %s type %s: %s\n", symbol.name, type_name, current == null ? "NOT RESOLVED" : current.name);
			return current != symbol ? current : null;
		}

		private Symbol? resolve_type_name_part (Symbol symbol, string type_name)
		{
			Symbol res = null, s = null;

			// test if it'is a generic type parameter
			// FIXME: this code is broken!
			Symbol curr_symbol = symbol;
			while (curr_symbol != null && curr_symbol != _codedom.root) {
				if (curr_symbol.name.has_prefix ("!") == false && curr_symbol.has_generic_type_arguments) {
					foreach (var arg in curr_symbol.generic_type_arguments) {
						if (type_name == arg.fully_qualified_name) {
							res = arg;
							break;
						}
					}
				}
				if (res != null) {
					break;
				}
				curr_symbol = curr_symbol.parent;
			}

			// namespace that contains this symbol are automatically in scope
			// from the inner one to the outmost
			if (res == null) {
				curr_symbol = symbol;
				while (curr_symbol != null && curr_symbol != _codedom.root) {
					if (curr_symbol.member_type == MemberType.CLASS ||
					    curr_symbol.member_type == MemberType.NAMESPACE ||
					    curr_symbol.member_type == MemberType.INTERFACE ||
					    curr_symbol.member_type == MemberType.STRUCT) {
						s = _codedom.symbols.@get ("%s.%s".printf (curr_symbol.fully_qualified_name, type_name));
						if (s != null && s != symbol) {
							res = s;
							break;
						}
					}
					curr_symbol = curr_symbol.parent;
				}
			}

			if (res == null) {
				// try with the imported namespaces
				bool has_glib_using = false;
				if (symbol.has_source_references) {
					foreach (SourceReference reference in symbol.source_references) {
						var file = reference.file;
						if (!file.has_using_directives) {
							continue;
						}

						foreach (DataType using_directive in file.using_directives) {
							if (using_directive.unresolved)
								continue;

							if (using_directive.name == "GLib") {
								has_glib_using = true;
							}

							//Utils.trace ("resolving with %s.%s".printf (using_directive.type_name, type.type_name));
							s = _codedom.symbols.@get ("%s.%s".printf (using_directive.type_name, type_name));
							if (s != null && s != symbol) {
								res = s;
								break;
							}
						}

						if (res != null) {
							break;
						}
					}
				}
				if (res == null) {
					if (!has_glib_using) {
						// GLib namespace is automatically imported
						s = _codedom.symbols.@get ("GLib.%s".printf (type_name));
						if (s != null && s != symbol) {
							res = s;
						}
					}
				}
			}

			return res;
		}

		private Symbol specialize_generic_symbol (DataType type, Symbol symbol)
		{
			var c = symbol.copy();
			visit_symbol (c);
			c.specialize_generic_symbol (type.generic_types);
			visit_symbol (c);
			if (c.has_base_types) {
				foreach (var item in c.base_types) {
					if (!item.unresolved) {
						if (item.symbol.has_generic_type_arguments) {
							if (item.symbol == symbol) {
								critical ("Skipping same instance reference cycle: %s %s",  symbol.description, item.type_name);
								continue;
							}
							if (item.symbol.fully_qualified_name == symbol.fully_qualified_name) {
								critical ("Skipping same name reference cycle: %s", item.symbol.description);
								continue;
							}
							//Utils.trace ("resolve generic type for %s: %s", symbol.fully_qualified_name, item.symbol.fully_qualified_name);

							item.symbol = specialize_generic_symbol (type, item.symbol);
						}
					}
				}
			}
			symbol.add_specialized_symbol (c);
			return c;
		}

		private void resolve_symbol (Afrodite.Symbol symbol, Afrodite.DataType type)
		{
			type.symbol = resolve_type (symbol, type);
			if (!type.unresolved) {
				if (type.symbol.return_type != null) {
					var dt = type.symbol.return_type;
					type.type_name = dt.type_name;
					if (type.is_iterator) {
						if (dt.has_generic_types && dt.generic_types.size == 1) {
							type.type_name = dt.generic_types[0].type_name;
							type.symbol = dt.generic_types[0].symbol;
						}
					}
				}

			}
		}

		private bool visit_symbol (Symbol symbol)
		{
			//print_symbol (symbol);
			bool resolved = true;
			
			// resolving base types
			if (symbol.has_base_types) {
				foreach (DataType type in symbol.base_types) {
					if (type.unresolved) {
						type.symbol = resolve_type (symbol, type);
						resolved &= !type.unresolved;
					}
				}
			}
			// resolving return type
			if (symbol.return_type != null) {
				if (symbol.return_type.unresolved) {
					symbol.return_type.symbol = resolve_type (symbol, symbol.return_type);
					resolved &= !symbol.return_type.unresolved;
				}
			}

			// resolving symbol parameters
			if (symbol.has_parameters) {
				foreach (DataType type in symbol.parameters) {
					if (type.unresolved) {
						type.symbol = resolve_type (symbol, type);
						resolved &= !type.unresolved;
					}
				}
			}
			// resolving local variables
			if (symbol.has_local_variables) {
				foreach (DataType type in symbol.local_variables) {
					if (type.unresolved) {
						resolve_symbol (symbol, type);
						resolved &= !type.unresolved;
					}
				}
			}
			
			return resolved;
		}

		/*
		private void visit_symbol (Symbol symbol)
		{
			//print_symbol (symbol);

			// resolving base types
			if (symbol.has_base_types) {
				foreach (DataType type in symbol.base_types) {
					if (type.unresolved) {
						type.symbol = resolve_type (symbol, type);
					}
				}
			}
			// resolving return type
			if (symbol.return_type != null) {
				if (symbol.return_type.unresolved) {
					symbol.return_type.symbol = resolve_type (symbol, symbol.return_type);
				}
			}

			// resolving symbol parameters
			if (symbol.has_parameters) {
				foreach (DataType type in symbol.parameters) {
					if (type.unresolved) {
						type.symbol = resolve_type (symbol, type);
					}
				}
			}
			// resolving local variables
			if (symbol.has_local_variables) {
				foreach (DataType type in symbol.local_variables) {
					if (type.unresolved) {
						resolve_symbol (symbol, type);
					}
				}
			}
			if (symbol.has_children) {
				visit_symbols (symbol.children);
			}
		}*/

		private void visit_symbols (Vala.List<unowned Afrodite.Symbol> symbols)
		{
			Vala.List<unowned Afrodite.Symbol> resolved = new Vala.ArrayList<unowned Afrodite.Symbol>();
			
			foreach (Symbol symbol in symbols) {
				if (visit_symbol (symbol)) {
					resolved.add (symbol);
				}
			}
			
			foreach (Symbol symbol in resolved)
				symbols.remove(symbol);
		}
	}
}
