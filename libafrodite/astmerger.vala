/* astmerger.vala
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
	internal class AstMerger : CodeVisitor
	{
		Afrodite.Symbol _current = null;
		Afrodite.DataType _current_type = null;
		unowned Afrodite.SourceReference _current_sr = null;
		Afrodite.SourceFile _source_file = null;
		Afrodite.DataType _inferred_type = null;
		
		string _vala_symbol_fqn = null;
		bool _merge_glib = true;
		bool _merge_edited_file = false;
		
		private Afrodite.CodeDom _codedom = null;

		public AstMerger (Afrodite.CodeDom codedom)
		{
			this._codedom = codedom;
		}

		public async void merge_vala_context (Vala.SourceFile source, CodeContext context, bool merge_glib, bool merge_edited_file)
		{
			_merge_glib = merge_glib;
			_merge_edited_file = merge_edited_file;
			_vala_symbol_fqn = null;
			_current_type = null;
			_current = _codedom.root;
			assert (_codedom.lookup_source_file (source.filename) == null);

			//debug ("COMPLETING FILE %s", source.filename);
			_source_file = _codedom.add_source_file (source.filename);
			foreach (UsingDirective u in source.current_using_directives) {
				_source_file.add_using_directive (u.namespace_symbol.to_string ());
			}
			yield visit_namespace_sliced (context.root);
		}

		private async void visit_namespace_sliced (Namespace ns)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			if (ns.name != null)
				_current = visit_symbol (MemberType.NAMESPACE, ns, out _current_sr);

			foreach (Enum en in ns.get_enums ()) {
				yield visit_enum_sliced (en);
			}

			foreach (ErrorDomain edomain in ns.get_error_domains ()) {
				edomain.accept (this);
			}

			foreach (Vala.Namespace n in ns.get_namespaces ()) {
				yield visit_namespace_sliced (n);
			}

			foreach (Vala.Class cl in ns.get_classes ()) {
				yield visit_class_sliced (cl);
			}

			foreach (Interface iface in ns.get_interfaces ()) {
				yield visit_interface_sliced (iface);
			}

			foreach (Struct st in ns.get_structs ()) {
				yield visit_struct_sliced (st);
			}

			foreach (Delegate d in ns.get_delegates ()) {
				yield visit_delegate_sliced (d);
			}

			foreach (Constant c in ns.get_constants ()) {
				yield visit_constant_sliced (c);
			}

			foreach (Field f in ns.get_fields ()) {
				yield visit_field_sliced (f);
			}

			foreach (Method m in ns.get_methods ()) {
				yield visit_method_sliced (m);
			}

			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}

		private async void visit_class_sliced (Class c)
		{
			visit_class (c);
		}

		private async void visit_struct_sliced (Struct st)
		{
			visit_struct (st);
		}

		private async void visit_interface_sliced (Interface iface)
		{
			visit_interface (iface);
		}

		private async void visit_method_sliced (Method m)
		{
			visit_method (m);
		}

		private async void visit_field_sliced (Field f)
		{
			visit_field (f);
		}

		private async void visit_constant_sliced (Constant c)
		{
			visit_constant (c);
		}

		private async void visit_enum_sliced (Enum e)
		{
			visit_enum (e);
		}

		private async void visit_delegate_sliced (Delegate d)
		{
			visit_delegate (d);
		}
		
		public override void visit_class (Class c)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;

			_current = visit_symbol (MemberType.CLASS, c, out _current_sr);
			_current.is_abstract = c.is_abstract;
			c.accept_children (this);
			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_struct (Struct s)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			_current = visit_symbol (MemberType.STRUCT, s, out _current_sr);
			s.accept_children (this);
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}

		private Afrodite.Symbol visit_symbol (MemberType type, Vala.Symbol s, out unowned Afrodite.SourceReference source_reference)
		{
			Afrodite.Symbol symbol;

			set_fqn (s.name);

			//NOTE: usually we should always add symbols but 
			// we should merge namespaces content.
			// This must be changed whenever vala will support 
			// partial classes.
			if (s.type_name != "ValaNamespace") {
				symbol = add_symbol (_current, type, s, out source_reference);
			} else {
				symbol = _codedom.lookup (_vala_symbol_fqn);
				if (symbol == null) {
					symbol = add_symbol (_current, type, s, out source_reference);
					//Utils.trace ("adding %s to source %s", symbol.fully_qualified_name, _source_file.filename);
				} else {
					source_reference = symbol.lookup_source_reference_filename (_source_file.filename);
					// add one more source reference to the symbol
					if (source_reference == null) {
						var sr = create_source_reference (s);
						symbol.add_source_reference (sr);
						source_reference = sr;
						//Utils.trace ("adding source reference %s to source %s", symbol.fully_qualified_name, _source_file.filename);
						_source_file.add_symbol (symbol);
					} else {
						warning ("two sources with the same name were merged %s: %s", symbol.fully_qualified_name, _source_file.filename);
					}
				}
			}
			return symbol;
		}
		
		private Afrodite.Symbol add_symbol (Afrodite.Symbol parent, MemberType type, Vala.Symbol s, out unowned Afrodite.SourceReference source_ref, int last_line = 0, int last_column = 0)
		{
			var name = s.name;
			
			if (name == null) {
				name = "%s:%s".printf(type.to_string ().down(), _current.fully_qualified_name);
			}
			
			var symbol = new Afrodite.Symbol (name, type);
			source_ref = symbol.lookup_source_reference_filename (_source_file.filename);
			if (source_ref == null) {
				var sr = create_source_reference (s, last_line, last_column);
				symbol.add_source_reference (sr);
				source_ref = sr;
			}
			symbol.access = get_vala_symbol_access (s.access);
			parent.add_child (symbol);
			_source_file.add_symbol (symbol);
			return symbol;
		}

		private Afrodite.Symbol add_codenode (Afrodite.Symbol parent, string name, MemberType type, Vala.CodeNode c, out unowned Afrodite.SourceReference source_ref, int last_line = 0, int last_column = 0)
		{
			var symbol = new Afrodite.Symbol (name, type);
			source_ref = symbol.lookup_source_reference_filename (_source_file.filename);
			if (source_ref == null) {
				var sr = create_source_reference (c, last_line, last_column);
				symbol.add_source_reference (sr);
				source_ref = sr;
			}
			symbol.access = Afrodite.SymbolAccessibility.PRIVATE;
			parent.add_child (symbol);
			_source_file.add_symbol (symbol);
			return symbol;
		}
		
		private Afrodite.SymbolAccessibility get_vala_symbol_access (Vala.SymbolAccessibility access)
		{
			switch (access) {
				case Vala.SymbolAccessibility.PRIVATE:
					return Afrodite.SymbolAccessibility.PRIVATE;
				case Vala.SymbolAccessibility.INTERNAL:
					return Afrodite.SymbolAccessibility.INTERNAL;
				case Vala.SymbolAccessibility.PROTECTED:
					return Afrodite.SymbolAccessibility.PROTECTED;
				case Vala.SymbolAccessibility.PUBLIC:
					return Afrodite.SymbolAccessibility.PUBLIC;
				default:
					warning ("Unknown vala symbol accessibility constant");
					return Afrodite.SymbolAccessibility.INTERNAL;
			}
		}

		private Afrodite.MemberBinding get_vala_member_binding (Vala.MemberBinding binding)
		{
			switch (binding) {
				case Vala.MemberBinding.INSTANCE:
					return Afrodite.MemberBinding.INSTANCE;
				case Vala.MemberBinding.CLASS:
					return Afrodite.MemberBinding.CLASS;
				case Vala.MemberBinding.STATIC:
					return Afrodite.MemberBinding.STATIC;
				default:
					warning ("Unknown vala member binding constant");
					return Afrodite.MemberBinding.INSTANCE;
			}
		}
		
		private Afrodite.SourceReference create_source_reference (Vala.CodeNode s, int last_line = 0, int last_column = 0)
		{
			var source_ref = new Afrodite.SourceReference ();
			source_ref.file = _source_file;
			int first_line = 0;
			int first_column = 0;
			
			if (s.source_reference != null) {
				first_line = s.source_reference.begin.line;
				first_column = s.source_reference.begin.column;
				if (last_line == 0)
					last_line = s.source_reference.end.line;
				if (last_column == 0)
					last_column = s.source_reference.end.column;
			}
			source_ref.first_line = first_line;
			source_ref.first_column = first_column;
			source_ref.last_line = last_line;
			source_ref.last_column = last_column;
			
			return source_ref;
		}

		private void set_fqn (string name)
		{
			if (_vala_symbol_fqn == null) {
				_vala_symbol_fqn = name;
			} else {
				_vala_symbol_fqn = _vala_symbol_fqn.concat (".", name);
			}
		}

		public override void visit_interface (Interface iface)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;

			_current = visit_symbol (MemberType.INTERFACE, iface, out _current_sr);
			iface.accept_children (this);
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		/*
		public override void visit_expression_statement (Vala.ExpressionStatement e)
		{
			e.accept_children (this);
		}
		
		public override void visit_method_call (Vala.MethodCall c)
		{
			//Utils.trace ("visit method call: %s", c.call.type_name);
			c.accept_children (this);
		}*/

		public override void visit_method (Method m)
		{
			//var timer = new Timer();
			//timer.start ();
			//Utils.trace ("visit method %s", m.name);

			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (m.name);
			int last_line = 0;
			if (m.body != null && m.body.source_reference != null)
				last_line = m.body.source_reference.end.line;
				
			var s = add_symbol (_current, MemberType.METHOD, m, out _current_sr, last_line);
			s.return_type = new DataType (m.return_type.to_string ());
			s.is_abstract = m.is_abstract;
			s.is_virtual = m.is_virtual;
			s.overrides = m.overrides;
			s.binding =  get_vala_member_binding (m.binding);
			
			_current = s;
			visit_type_for_generics (m.return_type, s.return_type);
			//Utils.trace ("visit method (symbol) %s: %f", m.name, timer.elapsed());
			//Utils.trace ("visit method (typeparam) %s: %f", m.name, timer.elapsed());
			foreach (TypeParameter p in m.get_type_parameters ()) {
				p.accept (this);
			}

			foreach (Vala.Parameter param in m.get_parameters ()) {
				param.accept (this);
			}
			//Utils.trace ("visit method (param) %s: %f", m.name, timer.elapsed());
			if (m.body != null) {
				// don't visit method body in vapi files if not required
				if (_merge_edited_file || _source_file.filename == null || !_source_file.filename.has_suffix (".vapi"))
					m.body.accept (this);
			}
			//Utils.trace ("visit method (body) %s: %f", m.name, timer.elapsed());
			
			// check if return type is generic
			var gt = _current.get_generic_type_argument (_current.return_type.type_name);
			if (gt != null) {
				_current.return_type.is_generic = true;
			}

			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
			//Utils.trace ("visit method %s: %f", m.name, timer.elapsed());
		}

		public override void visit_creation_method (CreationMethod m)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;

			set_fqn (m.name);
			int last_line = 0;
			if (m.body != null && m.body.source_reference != null)
				last_line = m.body.source_reference.end.line;
				
			var s = add_symbol (_current, MemberType.CREATION_METHOD, m, out _current_sr, last_line);
			if (m.name == ".new")
				s.return_type = new DataType (m.return_type.to_string ());

			else {
				// creation method
				s.return_type = new DataType (m.parent_symbol.get_full_name ());
			}
			s.is_abstract = m.is_abstract;
			s.is_virtual = m.is_virtual;
			s.overrides = m.overrides;
			if (m.name == ".new") {
				s.display_name = m.class_name;
			} else {
				s.display_name = "%s.%s".printf (m.class_name, m.name);
			}
			s.binding =  get_vala_member_binding (m.binding);
			s.return_type.symbol = _current;
			_current.add_resolved_target (s);
			
			_current = s;
			visit_type_for_generics (m.return_type, s.return_type);
			foreach (TypeParameter p in m.get_type_parameters ()) {
				p.accept (this);
			}

			foreach (Vala.Parameter param in m.get_parameters ()) {
				param.accept (this);
			}

			if (m.body != null) {
				m.body.accept (this);
			}

			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_constructor (Constructor m)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn ("constructor:%s".printf(_current.fully_qualified_name));
			int last_line = 0;
			if (m.body != null && m.body.source_reference != null)
				last_line = m.body.source_reference.end.line;
				
			var s = add_symbol (_current, MemberType.CONSTRUCTOR, m, out _current_sr, last_line);
			s.binding =  get_vala_member_binding (m.binding);
			s.return_type = new DataType (_current.fully_qualified_name);
			s.return_type.symbol = _current;
			_current.add_resolved_target (s);

			_current = s;
			if (m.body != null) {
				m.body.accept (this);
			}
			_current = prev;
			s.display_name = _current.name;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_destructor (Destructor m)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn ("destructor:%s".printf(_current.fully_qualified_name));
			int last_line = 0;
			if (m.body != null && m.body.source_reference != null)
				last_line = m.body.source_reference.end.line;
				
			var s = add_symbol (_current, MemberType.DESTRUCTOR, m, out _current_sr, last_line);
			s.binding =  get_vala_member_binding (m.binding);
			s.display_name = "~%s".printf (_current.display_name);
			 
			_current = s;
			if (m.body != null) {
				m.body.accept (this);
			}

			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_enum_value (Vala.EnumValue ev) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (ev.name);
			var sym = add_symbol (_current, MemberType.ENUM_VALUE, ev, out _current_sr);
			sym.access = _current.access;
			sym.binding = _current.binding;
			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_enum (Vala.Enum e) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (e.name);
			var s = add_symbol (_current, MemberType.ENUM, e, out _current_sr);
			_current = s;

			foreach (Vala.EnumValue value in e.get_values ()) {
				value.accept (this);
			}

			foreach (Method m in e.get_methods ()) {
				m.accept (this);
			}

			foreach (Constant c in e.get_constants ()) {
				c.accept (this);
			}

			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_delegate (Delegate d) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (d.name);
			var sym = add_symbol (_current, MemberType.DELEGATE, d, out _current_sr);
			sym.return_type = new DataType (d.return_type.to_string ());
			_current = sym;

			foreach (TypeParameter p in d.get_type_parameters ()) {
				p.accept (this);
			}
			foreach (Vala.Parameter param in d.get_parameters ()) {
				param.accept (this);
			}

			var gt = _current.get_generic_type_argument (_current.return_type.type_name);
			if (gt != null) {
				_current.return_type.is_generic = true;
			}
			
			//Utils.trace ("delegate: %s", _current.fully_qualified_name);
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}

	       	public override void visit_signal (Vala.Signal s) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (s.name);
			var sym = add_symbol (_current, MemberType.SIGNAL, s, out _current_sr);
			sym.return_type = new DataType (s.return_type.to_string ());
			sym.is_virtual = s.is_virtual;
			_current = sym;

			foreach (Vala.Parameter param in s.get_parameters ()) {
				param.accept (this);
			}
			if (s.default_handler == null && s.body != null) {
				s.body.accept (this);
			} else if (s.default_handler != null) {
				s.default_handler.accept (this);
			}

			var gt = _current.get_generic_type_argument (_current.return_type.type_name);
			if (gt != null) {
				_current.return_type.is_generic = true;
			}
			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_field (Field f) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			
			set_fqn (f.name);
			var s = add_symbol (_current, MemberType.FIELD, f, out _current_sr);
			s.return_type = new DataType (get_datatype_typename (f.variable_type));
			s.binding =  get_vala_member_binding (f.binding);
			_current = s;

			// check if return type is generic
			var gt = _current.get_generic_type_argument (_current.return_type.type_name);
			if (gt != null) {
				_current.return_type.is_generic = true;
			}
			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}

		public override void visit_constant (Vala.Constant c) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (c.name);
			var s = add_symbol (_current, MemberType.CONSTANT, c, out _current_sr);
			s.binding = MemberBinding.STATIC;
			s.return_type = new DataType (c.type_reference.to_string ());
			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
	
		public override void visit_property (Property p) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (p.name);
			int last_line = 0;
			if (p.get_accessor != null) {
				var body = p.get_accessor.body;
				if (body != null && body.source_reference != null)
					last_line = body.source_reference.end.line;
			}
			if (p.set_accessor != null) {
				var body = p.set_accessor.body;
				if (body != null && body.source_reference != null && body.source_reference.end.line > last_line)
					last_line = body.source_reference.end.line;
			}

			if (p.initializer != null) {
				if (p.initializer.source_reference != null && p.initializer.source_reference.end.line > last_line)
					last_line = p.initializer.source_reference.end.line;
			}

			var s = add_symbol (_current, MemberType.PROPERTY, p, out _current_sr, last_line);
			s.return_type = new DataType (p.property_type.to_string ());
			
			_current = s;
			if (p.get_accessor != null) {
				p.get_accessor.accept (this);
			}
			if (p.set_accessor != null) {
				p.set_accessor.accept (this);
			}

			if (p.initializer != null) {
				p.initializer.accept (this);
			}

			// check if return type is generic
			var gt = _current.get_generic_type_argument (_current.return_type.type_name);
			if (gt != null) {
				_current.return_type.is_generic = true;
			}
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
	
		public override void visit_property_accessor (PropertyAccessor a)
		{
			this.visit_scoped_codenode (a.readable ? "get" : "set", a, a.body);
		}
		
		public override void visit_error_domain (ErrorDomain ed)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
						
			set_fqn (ed.name);
			var s = add_symbol (_current, MemberType.ERROR_DOMAIN, ed, out _current_sr);
			
			_current = s;

			foreach (ErrorCode ecode in ed.get_codes()) {
				ecode.accept (this);
			}
			foreach (Method m in ed.get_methods ()) {
				m.accept (this);
			}

			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}
		
		public override void visit_error_code (ErrorCode ecode) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn (ecode.name);
			var s = add_symbol (_current, MemberType.ERROR_CODE, ecode, out _current_sr);
			s.access = _current.access;
			
			_current = prev;
			_current_sr = prev_sr;
			_vala_symbol_fqn = prev_vala_fqn;
		}

		private string? expression_to_string (Vala.Expression e)
		{
			if (e is Vala.Literal) {
				return e.to_string ();
			} else if (e is Vala.MemberAccess) {
				var ma = (Vala.MemberAccess) (e);
				return "%s".printf (ma.member_name);
			} else if (e is Vala.BinaryExpression) {
				var be = (Vala.BinaryExpression) e;
				return "%s %s %s".printf (expression_to_string (be.left), Utils.binary_operator_to_string (be.operator), expression_to_string (be.right));
			} else if (e is Vala.UnaryExpression) {
				var ue = (Vala.UnaryExpression) e;
				return "%s%s".printf (Utils.unary_operator_to_string (ue.operator), expression_to_string (ue.inner));
			} else {
				Utils.trace ("expression_to_string, unknown expression type: %s", e.type_name);
				return null;
			}
		}

		public override void visit_formal_parameter (Vala.Parameter p) 
		{
			DataType d;
			
			if (p.ellipsis) {
				d = Symbol.ELLIPSIS;
			} else {
				d = new DataType (get_datatype_typename (p.variable_type), p.name);
				if (p.initializer != null) {
					d.default_expression = expression_to_string (p.initializer);
				}
				switch (p.direction) {
					case Vala.ParameterDirection.OUT:
						d.is_out = true;
						break;
					case Vala.ParameterDirection.REF:
						d.is_ref = true;
						break;
				}
				d.is_array = p.variable_type.is_array ();
			}
			_current.add_parameter (d);
			
			// check if the parameter is a generic argument
			var gt = _current.get_generic_type_argument (d.type_name);
			if (gt != null) {
				d.is_generic = true;
			}
		}

		public override void visit_block (Block b) 
		{
			if (_current != null && _current_sr != null) {
				// see if this block extends a parent symbol
				if (b.source_reference != null && b.source_reference.end.line > _current_sr.last_line) {
					_current_sr.last_line = b.source_reference.end.line;
				}
			}
			b.accept_children (this);
		}
		
		public override void visit_local_variable (LocalVariable local) 
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;

			set_fqn (local.name);
			DataType s = new DataType ("", local.name);
			if (local.variable_type != null) {
				s.type_name = get_datatype_typename (local.variable_type);
			} else if (local.variable_type == null) {
				//Utils.trace ("infer from init '%s': %s", s.name, local.initializer.type_name);
				// try to resolve local variable type from initializers
				if (local.initializer != null) {
					var prev_inferred_type = _inferred_type;
					_inferred_type = s;

					local.initializer.accept (this);
					// HACK:
					if (s.type_name != null 
					    && (s.type_name.has_prefix ("this.") || s.type_name.has_prefix ("base.")))
					{
						s.type_name = s.type_name.substring (5);
					}

					// simplify binary expressions like: var a = "A" + method() + "B";
					// that returns string.string => string
					if (local.initializer is BinaryExpression && s.type_name != null) {
						string[] tmps = s.type_name.split(".");
						if (tmps.length <= 2) {
							s.type_name = tmps[0];
						} else {
							// here we simplify: "A" + "B" + object_constr_Test.field.to_string () + "C" + "D";
							// that returns Test.field.to_string.string => Test.field.to_string

							string type_name = "";
							for(int i=0; i < tmps.length - 1; i++) {
								type_name =  type_name.concat (tmps[i], ".");
							}
							s.type_name = type_name.substring(0, type_name.length - 1);
						}
					}
					_inferred_type = prev_inferred_type;
				}

				
				if (s.type_name != null && s.type_name.has_suffix ("Literal")) {
					if (s.type_name == "ValaIntegerLiteral") {
						s.type_name = "int";
					} else if (s.type_name == "ValaBooleanLiteral") {
						s.type_name = "bool";
					} else if (s.type_name == "ValaCharacterLiteral") {
						s.type_name = "char";
					} else if (s.type_name == "ValaStringLiteral") {
						s.type_name = "string";
					} else if (s.type_name == "ValaRealLiteral") {
						s.type_name = "double";
					}
				}
			}
			
			s.source_reference = this.create_source_reference (local);
			if (_current.has_local_variables) {
				 var old_var = _current.lookup_local_variable (s.name);
				 if (old_var != null) {
				 	//Utils.trace ("replacing local var: %s", s.name);
				 	_current.remove_local_variable (old_var);
				 }
			}
			//Utils.trace ("adding local var: %s to %s", s.name, _current.fully_qualified_name);
			_current.add_local_variable (s);
			if (local.variable_type != null)
				visit_type_for_generics (local.variable_type,s);
			_current = prev;
			_vala_symbol_fqn = prev_vala_fqn;
		}

		public override void visit_lambda_expression (LambdaExpression expr)
		{
			//debug ("visit lambda called");
			visit_scoped_codenode ("lambda-section", expr, null);
			//expr.accept_children (this);
		}

		public override void visit_member_access (MemberAccess expr) 
		{
			if (_inferred_type == null)
				return;

			string member_name = expr.member_name;
			//Utils.trace ("MemberAccess %s - %s: %s -> %s (%s)", _inferred_type.name, _current.name, expr.member_name,  expr.inner == null ? "TRUE" : "FALSE", expr.inner != null ? expr.inner.to_string() : "");
			if (expr.inner == null) {
				// Utils.trace (".\n");
				// this is the last iteration
				// lookup the name in all the visible symbols
				if (_current != null) {
					// try the first optimized path
					DataType d = _current.lookup_datatype_for_variable_name (CompareMode.EXACT, member_name);
					if (d != null) {
						member_name = d.type_name;
					} /* else if (_current.parent != null) {
						d = _current.parent.lookup_datatype_for_symbol_name (CompareMode.EXACT, member_name);
						if (d != null) {
							member_name = d.type_name;
						}*/ /* else {
							// this is the slowest path
							d = _current.scope_lookup_datatype_for_name (CompareMode.EXACT, member_name);
							if (d != null) {
								member_name = d.type_name;
							}
						}*/
					//}
				}
			}
			if (_inferred_type.type_name == null || _inferred_type.type_name == "") {
				_inferred_type.type_name = member_name;
			} else {
				_inferred_type.type_name = "%s.%s".printf (member_name, _inferred_type.type_name);
			}

			if (expr.inner != null) {
				expr.inner.accept (this);
			}
		}
		

		public override void visit_method_call (MethodCall mc)
		{
			mc.call.accept (this);
		}

		public override void visit_object_creation_expression (ObjectCreationExpression expr) 
		{
			expr.member_name.accept (this);
		}

		/*
		public override void visit_expression (Expression expr) 
		{
			// these expressions cause infinite recoursion
			if (expr is Vala.MemberAccess || expr is Vala.MethodCall || expr is Vala.BinaryExpression || expr is Vala.StringLiteral)
				return;

			debug ("visit expression %p, %s", expr, expr.type_name);
			expr.accept_children (this);
		}
		*/

		public override void visit_initializer_list (InitializerList list) 
		{
			list.accept_children (this);
		}
	
		public override void visit_binary_expression (BinaryExpression expr) 
		{
			expr.accept_children (this);
		}
		
		public override void visit_boolean_literal (BooleanLiteral lit) 
		{
			if (_inferred_type == null)
				return;
			
			if (_inferred_type.type_name == null || _inferred_type.type_name == "")
				_inferred_type.type_name = "bool";
		}


		public override void visit_character_literal (CharacterLiteral lit) 
		{
			if (_inferred_type == null)
				return;
				
			if (_inferred_type.type_name == null || _inferred_type.type_name == "")
				_inferred_type.type_name = "char";
		}

		public override void visit_integer_literal (IntegerLiteral lit) 
		{
			if (_inferred_type == null)
				return;

			if (_inferred_type.type_name == null || _inferred_type.type_name == "")
				_inferred_type.type_name = lit.type_name;
		}

		public override void visit_real_literal (RealLiteral lit) 
		{
			if (_inferred_type == null)
				return;
			if (_inferred_type.type_name == null || _inferred_type.type_name == "")
				_inferred_type.type_name = lit.get_type_name ();
		}

		public override void visit_string_literal (StringLiteral lit) 
		{
			if (_inferred_type == null)
				return;
			
			if (_inferred_type.type_name == null || _inferred_type.type_name == "")
				_inferred_type.type_name = "string";
		}
		
		public override void visit_declaration_statement (DeclarationStatement stmt)
		{
			stmt.accept_children (this);
		}

		public override void visit_foreach_statement (ForeachStatement stmt) 
		{
			var s = visit_scoped_codenode ("foreach", stmt, stmt.body);
			
			var d = new DataType ("", stmt.variable_name);
			if (stmt.type_reference == null) {
				var prev_inferred_type = _inferred_type;
				_inferred_type = d;

				stmt.accept_children (this);
				_inferred_type = prev_inferred_type;
			} else {
				d.type_name = get_datatype_typename (stmt.type_reference);
			}

			d.is_iterator = true;
			d.source_reference = create_source_reference (stmt);
			s.add_local_variable (d);
		}

		public override void visit_while_statement (WhileStatement stmt) 
		{
			visit_scoped_codenode ("while", stmt, stmt.body);
		}
		
		public override void visit_do_statement (DoStatement stmt) 
		{
			visit_scoped_codenode ("do", stmt, stmt.body);
		}
		
		public override void visit_for_statement (ForStatement stmt) 
		{
			visit_scoped_codenode ("for", stmt, stmt.body);
		}

		public override void visit_try_statement (TryStatement stmt) 
		{
			visit_scoped_codenode ("try", stmt, stmt.body);
		}
		
		public override void visit_catch_clause (CatchClause clause)
		{
			var s = visit_scoped_codenode ("catch", clause, clause.body);
			var d = new DataType (get_datatype_typename (clause.error_type), clause.variable_name);
			s.add_local_variable (d);
		}
		
		public override void visit_if_statement (IfStatement stmt) 
		{
			visit_scoped_codenode ("if", stmt, stmt.true_statement);
			if (stmt.false_statement != null)
				visit_scoped_codenode ("else", stmt, stmt.false_statement);
		}

		public override void visit_switch_statement (SwitchStatement stmt) 
		{
			visit_scoped_codenode ("switch", stmt, null);
		}

		public override void visit_switch_section (SwitchSection section) 
		{
			visit_scoped_codenode ("switch-section", section, section); // a section is also a block
		}

		public override void visit_type_parameter (TypeParameter p)
		{
			/*
			var d = new DataType (get_datatype_typename (p), p.name);
			switch (p.direction) {
				case Vala.ParameterDirection.OUT:
					d.is_out = true;
					break;
				case Vala.ParameterDirection.REF:
					d.is_ref = true;
					break;
			}*/

			var symbol = new Afrodite.Symbol (p.name, MemberType.TYPE_PARAMETER);
			symbol.access = SymbolAccessibility.ANY;

			//Utils.trace ("adding type parameter: '%s' to '%s'", p.name, _current.fully_qualified_name);
			_current.add_generic_type_argument (symbol);
			p.accept_children (this);
		}


		public override void visit_data_type (Vala.DataType type)
		{
			var t = new Afrodite.DataType (get_datatype_typename (type), null);
			if (_current_type != null) {
				//debug ("adding gen type %s %s %s", _current.name, get_datatype_typename (type), Type.from_instance (type).name ());
				_current_type.add_generic_type (t);
				
			} else if (_current != null
				&& (_current.member_type == MemberType.CLASS || _current.member_type == MemberType.INTERFACE || _current.member_type == MemberType.STRUCT)) {
				// add this type to the base class types
				if (t.type_name.length == 1 && t.type_name.up () == t.type_name) {
					// there's must be a better method
					Utils.trace ("You should fix this hack: %s - %s: '%s' to '%s'",
					type.type_name,
					type.type_parameter != null ? type.type_parameter.to_string () : "type parameter is null",
					t.type_name,
					_current.fully_qualified_name);
				} else {
					_current.add_base_type (t);
					visit_type_for_generics (type, t);
				}
			}
		}
		
		private void visit_type_for_generics (Vala.DataType t, Afrodite.DataType ct) 
		{
			var prev_type = _current_type;
			_current_type = ct;
			foreach (Vala.DataType type in t.get_type_arguments ()) {
				type.accept (this);
			}
			_current_type = prev_type;
		}
		
		private Afrodite.Symbol visit_scoped_codenode (string name, CodeNode node, Block? body)
		{
			var prev_vala_fqn = _vala_symbol_fqn;
			var prev = _current;
			unowned SourceReference prev_sr = _current_sr;
			
			set_fqn ("!%s".printf (name));
			int last_line = 0;
			if (body != null && body.source_reference != null) {
				last_line = body.source_reference.end.line;
				//debug ("body for %s: %d,%d to %d,%d\n", name, body.source_reference.first_line, body.source_reference.first_column, body.source_reference.last_line, body.source_reference.last_column);
			}
				
			var s = add_codenode (_current, "!%s".printf(name), MemberType.SCOPED_CODE_NODE, node, out _current_sr, last_line);
			//s.display_name = name;
			_current = s;
			if (body == null) {
				node.accept_children (this);
			} else {
				body.accept_children (this);
			}
			_current = prev;
			_current_sr = prev_sr;
			
			_vala_symbol_fqn = prev_vala_fqn;
			
			return s;
		}

		private string get_datatype_typename (Vala.DataType? type)
		{
			if (type is UnresolvedType) {
				return ((UnresolvedType) type).unresolved_symbol.to_string ();
			} else if (type == null) {
				return "DataType is null: %s".printf (_vala_symbol_fqn);
			} else {
				return type.to_string ();
			}
		}
	}
}
