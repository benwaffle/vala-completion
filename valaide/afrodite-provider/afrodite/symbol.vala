/* symbol.vala
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
	public class Symbol
	{
		public static VoidType VOID = new VoidType ();
		public static EllipsisType ELLIPSIS = new EllipsisType ();

		private unowned Symbol _parent;
		public unowned Symbol parent {
			get { return _parent; }
			set {
				assert (value != this);
				_parent = value;
			}
		}

		public Vala.List<Symbol> children { get; set; }
		// contains a reference to symbols of whose this symbol is a resolved reference for any target data type
		public Vala.List<unowned Symbol> resolved_targets = null;

		// contains a reference to symbols that this symbol use as resolved targets
		public Vala.List<unowned Symbol> resolve_targets = null;

		public unowned Symbol? generic_parent { get; set; }
		
		public string name { get; set; }
		public string fully_qualified_name { get; set; }
		
		public DataType return_type { get; set; } // real symbol return type
		public string type_name { get; set; }
		
		public Vala.List<SourceReference> source_references { get; set; }
		public Vala.List<DataType> parameters { get; set; }
		public Vala.List<DataType> local_variables { get; set; }
		public Vala.List<DataType> base_types { get; set; }
		public Vala.List<Symbol> generic_type_arguments { get; set; }
		public bool is_generic_type_argument { get; set; }

		public SymbolAccessibility access {
			get{ return _access; }
			set{ _access = value; }
		}
		private SymbolAccessibility _access = SymbolAccessibility.INTERNAL;
		public MemberBinding binding = MemberBinding.INSTANCE;
		public bool is_virtual = false;
		public bool is_abstract = false;
		public bool overrides = false;
		internal int _static_child_count = 0;
		internal int _creation_method_child_count = 0;

		private string _info = null;
		private string _des = null;
		private string _markup_des = null;
		private string _display_name = null;
		
		private DataType _symbol_type = null;
		
		private Vala.List<Symbol> _specialized_symbols = null;

		public bool is_root
		{
			get {
				return fully_qualified_name == null;
			}
		}

		public DataType symbol_type {
			get {
				if (_symbol_type == null)
					return return_type;
					
				return _symbol_type;
			}
		}

		public Symbol (string? fully_qualified_name, string? type_name)
		{
			if (fully_qualified_name != null) {
				string[] parts = fully_qualified_name.split (".");
				name = parts[parts.length-1];
				this.fully_qualified_name = fully_qualified_name;
			}
			if (type_name != null && type_name.has_prefix ("Vala"))
				this.type_name = type_name.substring (4);
			else
				this.type_name = type_name;

			if (this.type_name == "Signal") {
				_symbol_type = Afrodite.Utils.Symbols.get_predefined ().signal_type;
			}
		}
		
		~Symbol ()
		{
			// Utils.trace ("Symbol destroy: %s (%p)", _fully_qualified_name, this);
			// parent and generic parent if this symbol is a specialization
			if (parent != null) {
				if (is_generic_type_argument) {
					if (parent.has_generic_type_arguments) {
						parent.remove_generic_type_argument (this);
					}
				} else {
					if (parent.has_children) {
						parent.remove_child (this);
					}
				}
			}

			if (generic_parent != null && generic_parent.has_specialized_symbols) {
				generic_parent.remove_specialized_symbol (this);
			}

			// unresolve all the targets. direction target *is resolved by* this symbol
			if (has_resolved_targets) {
				foreach(var symbol in resolved_targets) {
					symbol.unresolve_symbols_of_target (this);
					if (symbol.resolve_targets != null) {
						symbol.resolve_targets.remove (this);
					}
				}
			}

			// remove this symbol from all resolving symbols
			while (resolve_targets != null && resolve_targets.size > 0) {
				var symbol = resolve_targets.get (0);
				symbol.remove_resolved_target (this);
			}

			// the same for generic type arguments
			if (has_generic_type_arguments) {
				foreach(var symbol in generic_type_arguments) {
					symbol.unresolve_symbols_of_target (this);
					symbol.parent = null;
				}
			}

			this.remove_from_targets ();

			while (has_source_references) {
				int prev_size = source_references.size;
				var sr = source_references.get (0);
				if (sr.file.has_symbols) {
					sr.file.remove_symbol (this); // this will remove the source reference from the symbol
				} else {
					critical ("%s belong to source %p but it isn't listed in its symbol table. Leak?", this.fully_qualified_name, sr.file);
					// if the source reference wasn't removed remove it by hand!
					remove_source_reference (sr);
				}
				if (has_source_references) {
					assert (source_references.size < prev_size);
				}
			}

			// deallocate the children
			if (has_children) {
				foreach (Symbol child in children) {
					if (child.parent == this) {
						child.parent = null;
					}
				}
				children = null;
			}

			if (has_specialized_symbols) {
				foreach (Symbol sym in _specialized_symbols) {
					if (sym.generic_parent == this) {
						sym.generic_parent = null;
					}
				}
			}

			//Utils.trace ("Symbol destroyied: %s (%p)", _fully_qualified_name, this);
		}

		private void remove_from_targets ()
		{
			// remove myself from all resolve target list. direction this *is a resolution for* target
			if (_return_type != null && !_return_type.unresolved) {
				_return_type.symbol = null;
			}

			if (this.has_parameters) {
				foreach (var item in parameters) {
					if (!item.unresolved) {
						item.symbol = null;
					}
				}
			}

			if (this.has_local_variables) {
				foreach (var item in local_variables) {
					if (!item.unresolved) {
						item.symbol = null;
					}
				}
			}

			if (this.has_base_types) {
				foreach (var item in base_types) {
					if (!item.unresolved) {
						item.symbol = null;
					}
				}
			}

			if (_symbol_type != null && !_symbol_type.unresolved) {
				_symbol_type.symbol = null;
			}
		}

		private void unresolve_datatype_of_target (Vala.List<DataType> items, Symbol target)
		{
			foreach(DataType item in items) {
				if (item.has_generic_types) {
					foreach (DataType generic_item in item.generic_types) {
						if (generic_item.symbol == target) {
							generic_item.symbol = null;
						}
					}
				}
				if (item.symbol == target) {
					item.symbol = null;
				}
			}
		}

		private void unresolve_symbols_of_target (Symbol target)
		{
			if (_return_type != null) {
				if (_return_type.symbol == target) {
					_return_type.symbol = null;
				}
			}

			if (has_parameters) {
				unresolve_datatype_of_target (parameters, target);
			}

			if (has_local_variables) {
				unresolve_datatype_of_target (local_variables, target);
			}

			if (has_base_types) {
				unresolve_datatype_of_target (base_types, target);
			}

			if (_symbol_type != null && _symbol_type.symbol == target)
				_symbol_type.symbol = null;
		}

		public int static_child_count
		{
			get {
				return _static_child_count;
			}
			set {
				var delta = value - _static_child_count;
				_static_child_count = value;
				if (parent != null)
					parent.static_child_count += delta;
			}
		}

		public int creation_method_child_count
		{
			get {
				return _creation_method_child_count;
			}
			set {
				var delta = value - _creation_method_child_count;
				_creation_method_child_count = value;
				if (parent != null)
					parent.creation_method_child_count += delta;
			}
		}

		public void add_child (Symbol child)
		{
			assert (child != this);
			if (children == null) {
				children = new ArrayList<Symbol> ();
			}

			children.add (child);
			child.parent = this;
			if (child.is_static || child.has_static_child) {
				static_child_count++;
			}
			if (child.type_name == "CreationMethod" || child.has_creation_method_child) {
				creation_method_child_count++;
			}
		}
		
		public void remove_child (Symbol child)
		{
			children.remove (child);
			if (child.parent == this)
				child.parent = null;

			if (children.size == 0)
				children = null;
				
			if (_static_child_count > 0
				&& (child.is_static || child.has_static_child)) {
				static_child_count--;
			}
			if (_creation_method_child_count > 0 
				&& (child.type_name == "CreationMethod" || child.has_creation_method_child)) {
				creation_method_child_count++;
			}
		}
		
		public Symbol? lookup_child (string name)
		{
			if (has_children) {
				foreach (Symbol s in children) {
					if (s.name == name) {
						return s;
					}
				}
			}
			return null;
		}

		public DataType? lookup_datatype_for_variable_name (CompareMode mode, string name, SymbolAccessibility access = SymbolAccessibility.ANY)
		{
			if (has_local_variables) {
				foreach (DataType d in local_variables) {
					if (compare_symbol_names (d.name, name, mode)) {
						return d;
					}
				}
			}

			// search in symbol parameters
			if (has_parameters) {
				foreach (DataType type in parameters) {
					if (compare_symbol_names (type.name, name, mode)) {
						return type;
					}
				}
			}
			
			return null;
		}

		public DataType? lookup_datatype_for_symbol_name (CompareMode mode, string name, SymbolAccessibility access = SymbolAccessibility.ANY)
		{
			if (has_children) {
				foreach (Symbol s in this.children) {
					if ((s.access & access) != 0
					    && compare_symbol_names (s.name, name, mode)) {
						return s.return_type;
					}
				}
			}
			
			if (has_base_types) {
				foreach (DataType d in this.base_types) {
					if (d.symbol != null) {
						var r = d.symbol.lookup_datatype_for_symbol_name (mode, name, 
							SymbolAccessibility.INTERNAL | SymbolAccessibility.PROTECTED | SymbolAccessibility.PROTECTED);
						if (r != null) {
							return d;
						}
					}
				}
			}
			return null;
		}

		public DataType? lookup_datatype_for_name (CompareMode mode, string name, SymbolAccessibility access = SymbolAccessibility.ANY)
		{
			var result = lookup_datatype_for_variable_name (mode, name, access);
			if (result != null)
				return result;

			return lookup_datatype_for_symbol_name (mode, name, access);
		}
		
		public DataType? scope_lookup_datatype_for_name (CompareMode mode, string name)
		{
			DataType result = lookup_datatype_for_name (mode, name);
			
			if (result == null) {

				if (this.parent != null) {
					result = this.parent.scope_lookup_datatype_for_name (mode, name);
				}
				
				if (result == null) {
					// search in the imported namespaces
					if (this.has_source_references) {
						foreach (SourceReference s in this.source_references) {
							if (s.file.has_using_directives) {
								foreach (var u in s.file.using_directives) {
									if (!u.unresolved) {
										result = u.symbol.lookup_datatype_for_symbol_name (mode, name, SymbolAccessibility.INTERNAL | SymbolAccessibility.PUBLIC);
										if (result != null) {
											break;
										}
									}
								}
							}

							if (result != null) {
								break;
							}
						}
					}
				}
			}
			return result;
		}
		
		private static bool compare_symbol_names (string? name1, string? name2, CompareMode mode)
		{
			if (mode == CompareMode.START_WITH && name1 != null && name2 != null) {
				return name1.has_prefix (name2);
			} else {
				return name1 == name2;
			}
		}
		
		public bool has_children
		{
			get {
				return children != null;
			}
		}


		public void add_resolved_target (Symbol resolve_target)
		{
			assert (resolve_target != this);

			// resolve target collection can be accessed from multiple threads
			lock (resolved_targets) {
				if (resolved_targets == null) {
					resolved_targets = new ArrayList<unowned Symbol> ();
				}

				if (!resolved_targets.contains (resolve_target))
					resolved_targets.add (resolve_target);

				if (resolve_target.resolve_targets == null) {
					resolve_target.resolve_targets = new ArrayList<unowned Symbol> ();
				}

				if (!resolve_target.resolve_targets.contains (this))
					resolve_target.resolve_targets.add (this);
			}
		}

		public void remove_resolved_target (Symbol resolve_target)
		{
			// resolve target collection can be accessed from multiple threads
			lock (resolved_targets) {
				resolved_targets.remove (resolve_target);
				if (resolved_targets.size == 0)
					resolved_targets = null;

				if (resolve_target.resolve_targets != null) {
					resolve_target.resolve_targets.remove (this);

					if (resolve_target.resolve_targets.size == 0)
						resolve_target.resolve_targets = null;
				}
			}
		}

		public bool has_resolved_targets
		{
			get {
				bool res;
				
				lock (resolved_targets) {
					res = resolved_targets != null;
				}
				
				return res;
			}
		}

		public void add_parameter (DataType par)
		{
			if (parameters == null) {
				parameters = new ArrayList<DataType> ();
			}
			
			parameters.add (par);
		}
		
		public void remove_parameter (DataType par)
		{
			parameters.remove (par);
			if (parameters.size == 0)
				parameters = null;
		}

		public bool has_parameters
		{
			get {
				return parameters != null;
			}
		}
		
		public void add_generic_type_argument (Symbol sym)
		{
			assert (sym != this);
			if (generic_type_arguments == null) {
				generic_type_arguments = new ArrayList<Symbol> ();
			}

			//debug ("added generic %s to %s", sym.name, this.fully_qualified_name);
			//Utils.trace ("add generic type args symbol %s: %s", _fully_qualified_name, sym.fully_qualified_name);
			generic_type_arguments.add (sym);
			sym.is_generic_type_argument = true;
			sym.parent = this;
		}
		
		public void remove_generic_type_argument (Symbol sym)
		{
			assert (sym != this);
			generic_type_arguments.remove (sym);
			if (sym.parent == this) {
				sym.parent = null;
			}
			if (generic_type_arguments.size == 0)
				generic_type_arguments = null;
		}

		public bool has_generic_type_arguments
		{
			get {
				return generic_type_arguments != null;
			}
		}
		
		public void add_local_variable (DataType variable)
		{
			if (local_variables == null) {
				local_variables = new ArrayList<DataType> ();
			}
			
			local_variables.add (variable);
		}
		
		public void remove_local_variable (DataType variable)
		{
			local_variables.remove (variable);
			if (local_variables.size == 0)
				local_variables = null;
		}

		public DataType? lookup_local_variable (string name)
		{
			if (has_local_variables) {
				foreach (DataType d in _local_variables) {
					if (d.name == name) {
						return d;
					}
				}
			}
			return null;
			
		}

		public bool has_local_variables
		{
			get {
				return local_variables != null;
			}
		}

		public void add_base_type (DataType type)
		{
			if (base_types == null) {
				base_types = new ArrayList<DataType> ();
			}
			
			base_types.add (type);
		}
		
		public void remove_base_type (DataType type)
		{
			base_types.remove (type);
			if (base_types.size == 0)
				base_types = null;
		}

		public bool has_base_types
		{
			get {
				return base_types != null;
			}
		}

		public void add_source_reference (SourceReference reference)
		{
			if (source_references == null) {
				source_references = new ArrayList<SourceReference> ();
			}
			source_references.add (reference);
		}
		
		public void remove_source_reference (SourceReference reference)
		{
			source_references.remove (reference);
			if (source_references.size == 0) {
				source_references = null;
			}
		}
		
		public unowned SourceReference? lookup_source_reference_filename (string filename)
		{
			unowned SourceReference? result = null;
			if (has_source_references) {
				foreach (SourceReference reference in source_references) {
					if (reference.file.filename == filename)
						result = reference;
						break;
				}
			}
			
			return result;
		}
		
		public SourceReference? lookup_source_reference_sourcefile (SourceFile source)
		{
			if (has_source_references) {
				foreach (SourceReference reference in source_references) {
					if (reference.file == source)
						return reference;
				}
			}
			
			return null;
		}

		public bool has_source_references
		{
			get {
				return source_references != null;
			}
		}

		public bool has_static_child
		{
			get {
				return _static_child_count > 0;
			}
		}

		public bool has_creation_method_child
		{
			get {
				return _creation_method_child_count > 0;
			}
		}
		
		public bool is_static
		{
			get {
				return (binding & MemberBinding.STATIC) != 0;
			}
		}

		public bool check_options (QueryOptions? options)
		{
			if (name != null && name.has_prefix ("*")) // vala added symbols like signal.connect or .disconnect
				return true;
				
			if (options.exclude_code_node && (name == null || name.has_prefix ("!")))
				return false;

			if (options.all_symbols)
				return true;
			
			if ((access & options.access) != 0) {
				if (options.only_static_factories 
					&& ((!is_static && !has_static_child))) {
					//debug ("excluded only static %s: %s", this.type_name, this.fully_qualified_name);
					return false;
				}
				if (options.only_creation_methods 
					&& type_name != "CreationMethod"
					&& type_name != "ErrorDomain"
					&& !has_creation_method_child) {
					//debug ("excluded only creation %s: %d, %s", type_name, this.creation_method_child_count, this.fully_qualified_name);
					return false;
				}
				if (options.exclude_creation_methods && type_name == "CreationMethod") {
					//debug ("excluded exclude creation %s: %s", type_name, this.fully_qualified_name);
					return false;
				}
				if (type_name == "Destructor") {
					return false;
				}

				if ((binding & options.binding) == 0)
					return false;

				return true;
			}
			//debug ("excluded symbol access %s: %s", type_name, this.fully_qualified_name);
			return false;
		}
		
		public string description
		{
			get {
				if (_des == null)
					_des = build_description (false);
				
				return _des;
			}
		}

		public string markup_description
		{
			get {
				if (_markup_des == null)
					_markup_des = build_description (true);
				
				return _markup_des;
			}
		}

		public string info
		{
			get {
				if (_info == null)
					_info = build_info ();
				
				return _info;
			}
		}
		
		public string display_name
		{
			get {
				if (_display_name == null) {
					return name;
				}
				
				return _display_name;
			}
			set {
				_display_name = value;
			}
		}

		internal string build_info ()
		{
			if (type_name == "Class")
			{
				var s = get_default_constructor ();
				if (s != null) {
					return s.build_info ();
				}
			}
			
			int param_count = 0;
			string params;
			string generic_args;
			
			StringBuilder sb = new StringBuilder ();

			if (has_generic_type_arguments) {
				sb.append ("&lt;");
				foreach (Symbol s in generic_type_arguments) {
					sb.append_printf ("%s, ", s.description);
				}
				sb.truncate (sb.len - 2);
				sb.append ("&gt;");
				generic_args = sb.str;
				sb.truncate (0);
				
			} else {
				generic_args = "";
			}
			
			if (has_parameters) {
				param_count = parameters.size;
				
				string sep;
				if (param_count > 2) {
					sep = "\n";
				} else {
					sep = " ";
				}
				
				foreach (DataType type in parameters) {
					sb.append_printf ("%s,%s", type.description, sep);
				}
				sb.truncate (sb.len - 2);
				params = sb.str; 
				sb.truncate (0);
			} else {
				params = "";
			}
			
			string return_type_descr = "";
			string type_name_descr = type_name;
			
			if (return_type != null) {
				if (type_name == "CreationMethod") {
					type_name_descr = _("Class");
				} else {
					return_type_descr = return_type.description;
				}
			}
			
			sb.append_printf("%s: %s\n\n%s%s<b>%s</b> %s (%s%s)",
				    type_name_descr,
				    display_name,
				    return_type_descr,
				    (param_count > 2 ? "\n" : " "),
				    display_name, generic_args,
				    (param_count > 2 ? "\n" : ""),
				    params);
				    
			if (type_name != null && !type_name.has_suffix ("Method")) {
				sb.truncate (sb.len - 3);
			}

			return sb.str;
		}
		
		private string build_description (bool markup)
		{
			var sb = new StringBuilder ();
			if (type_name != "EnumValue") {
				sb.append (this.access_string);
				sb.append (" ");
				if (binding_string != "") {
					sb.append (binding_string);
					sb.append (" ");
				}
			}
			
			if (return_type != null) {
				if (type_name == "Constructor") {
					sb.append ("constructor: ");
				} else
					sb.append_printf ("%s ", return_type.description);
			}
			if (markup 
			    && type_name != null
			    && (type_name == "Property" 
			    || type_name.has_suffix ("Method")
			    || type_name.has_suffix ("Signal")
			    || type_name == "Field"
			    || type_name == "Constructor"))
				sb.append_printf ("<b>%s</b>".printf(display_name));
			else
				sb.append (display_name);

			if (has_generic_type_arguments) {
				sb.append ("&lt;");
				foreach (Symbol s in generic_type_arguments) {
					sb.append_printf ("%s, ", s.name);
				}
				sb.truncate (sb.len - 2);
				sb.append ("&gt;");
			}
			
			if (type_name != null 
				&& (has_parameters || type_name.has_suffix ("Method") || type_name.has_suffix("Signal"))) {
				sb.append (" (");
			}
			if (has_parameters) {
				foreach (DataType type in parameters) {
					sb.append_printf ("%s, ", type.description);
				}
				sb.truncate (sb.len - 2);
			}
			if (type_name != null
				&& (has_parameters || type_name.has_suffix ("Method") || type_name.has_suffix("Signal"))) {
				sb.append (")");
			}
			
			if (has_base_types) {
				sb.append (" : ");
				foreach (DataType type in base_types) {
					sb.append_printf ("%s, ", type.description);
				}
				sb.truncate (sb.len - 2);
			}
			
			return sb.str;
		}
		
		public string access_string
		{
			owned get {
				string res;
				
				switch (access) {
					case Afrodite.SymbolAccessibility.PRIVATE:
						res = "private";
						break;
					case Afrodite.SymbolAccessibility.INTERNAL:
						res = "internal";
						break;
					case Afrodite.SymbolAccessibility.PROTECTED:
						res = "protected";
						break;
					case Afrodite.SymbolAccessibility.PUBLIC:
						res = "public";
						break;
					default:
						res = "unknown";
						break;
				}
				return res;
			}
		}
		
		public string binding_string
		{
			owned get {
				string res;
				
				switch (binding) {
					case Afrodite.MemberBinding.CLASS:
						res = "class";
						break;
					case Afrodite.MemberBinding.INSTANCE:
						res = "";
						break;
					case Afrodite.MemberBinding.STATIC:
						res = "static";
						break;
					default:
						res = "unknown";
						break;
				}	
				return res;
			}
		}
		
		public Symbol? get_default_constructor ()
		{
			if (has_children) {
				foreach (Symbol s in _children) {
					if (s.name == "new") {
						return s;
					}
				}
			}
			
			return null;
		}

		public Symbol copy ()
		{
			var res = new Symbol (_fully_qualified_name, type_name);
			res.type_name = this.type_name;
			res.parent = this.parent;

			res.name = this.name;
			res.fully_qualified_name = this.fully_qualified_name;
			if (_return_type != null) {
				res.return_type = _return_type.copy ();
			}

			res.access = this.access;
			res.binding = this.binding;

			res.is_virtual = this.is_virtual;
			res.is_abstract = this.is_abstract;
			res.overrides = this.overrides;

			res._symbol_type = _symbol_type;
			res._static_child_count = this._static_child_count;
			res._creation_method_child_count = this._creation_method_child_count;

			if (has_children) {
				foreach(var item in children) {
					var s = item.copy ();
					res.add_child (s);
				}
			}

			if (has_source_references) {
				foreach (var item in source_references) {
					res.add_source_reference (item);
				}
			}

			if (has_parameters) {
				foreach (var item in parameters) {
					res.add_parameter (item.copy ());
				}
			}

			if (has_local_variables) {
				foreach (var item in local_variables) {
					res.add_local_variable (item.copy ());
				}
			}

			if (has_base_types) {
				foreach (var item in base_types) {
					var d = item.copy ();
					res.add_base_type (d);
				}
			}

			if (generic_type_arguments != null) {
				foreach (var item in generic_type_arguments) {
					res.add_generic_type_argument (item.copy ());
				}
			}

			return res;
		}

		public void specialize_generic_symbol (Vala.List<DataType> types)
		{
			// assign the real types
			for(int i = 0; i < types.size; i++) {
				//Utils.trace ("resolve generic type: %s", types[i].type_name);
				if (this.generic_type_arguments.size <= i) {
					break;
				}
				string name = this.generic_type_arguments[i].fully_qualified_name ?? this.generic_type_arguments[i].name;
				resolve_generic_type (this, name, types[i]);
				this.generic_type_arguments[i].fully_qualified_name = types[i].type_name;
				this.generic_type_arguments[i].name  = types[i].type_name;
				this.generic_type_arguments[i].return_type = types[i];
				this._des = null;
				this._info = null;
				this._markup_des = null;
			}
		}

		public void add_specialized_symbol (Symbol? item)
		{
			assert (item != this);

			if (_specialized_symbols == null)
				_specialized_symbols = new Vala.ArrayList<Symbol> ();

			_specialized_symbols.add (item);
			item.generic_parent = this;
		}

		public void remove_specialized_symbol (Symbol? item)
		{
			assert (item != this);

			_specialized_symbols.remove (item);
			if (item.generic_parent == this)
				item.generic_parent = null;

			if (_specialized_symbols.size == 0)
				_specialized_symbols = null;
		}

		public bool has_specialized_symbols
		{
			get {
				 return _specialized_symbols != null;
			}
		}

		private void resolve_generic_type (Symbol symbol, string generic_type_name, DataType type)
		{
			if (symbol.return_type != null) {
				//Utils.trace ("symbol %s return type %s generic type %s, resolved with %s", symbol.fully_qualified_name, symbol.return_type.type_name, generic_type_name, type.type_name);
				if (symbol.return_type.type_name == generic_type_name)
					symbol.return_type = type;
				/*
				else if (!symbol.return_type.unresolved) {
					Utils.trace ("resolve generic types %s %s: %s", symbol.return_type.type_name, generic_type_name, type.type_name);
					resolve_generic_type(symbol.return_type.symbol, generic_type_name, type);
				}
				*/
			}

			if (symbol.has_children) {
				foreach (var item in symbol.children) {
					if (item.return_type != null && item.return_type.type_name == generic_type_name) {
						item.return_type = type;
					}
					if (item.has_parameters) {
						foreach (var par in item.parameters) {
							if (par.type_name == generic_type_name) {
								par.type_name = type.type_name;
								par.name = type.name;
								par.symbol = type.symbol;

							}
						}
					}
					if (item.has_children) {
						resolve_generic_type (item, generic_type_name, type);
					}
				}
			}
			if (symbol.has_local_variables) {
				foreach (var item in symbol.local_variables) {
					if (item.type_name == generic_type_name) {
						item.type_name = type.type_name;
						item.symbol = type.symbol;
					}
				}
			}
			if (symbol.has_parameters) {
				foreach (var item in symbol.parameters) {
					if (item.type_name == generic_type_name) {
						item.type_name = type.type_name;
						item.name = type.type_name;
						item.symbol = type.symbol;
					}
				}
			}
		}
	}
}
