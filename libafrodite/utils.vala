/* utils.vala
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

namespace Afrodite.Utils
{
	/**
	 * This function shouldn't be used directly but just wrapped with a private one that
	 * will specify the correct log domain. See the function trace (...) in this same source 
	 */
	public static inline void log_message (string log_domain, string format, va_list args)
	{
		logv (log_domain, GLib.LogLevelFlags.LEVEL_INFO, format, args);
	}

	[Diagnostics]
	[PrintfFormat]
	internal static inline void trace (string format, ...)
	{
#if DEBUG
		var va = va_list ();
		var va2 = va_list.copy (va);
		log_message ("Afrodite", format, va2);
#endif
	}

	public static Vala.List<string>? get_package_paths (string pkg, CodeContext? context = null, string[]? vapi_dirs = null)
	{
		var ctx = context;
		if (ctx == null) {
			ctx = new Vala.CodeContext();
		}

		ctx.vapi_directories = vapi_dirs;
		var package_path = ctx.get_vapi_path (pkg);
		if (package_path == null) {
			return null;
		}
		
		var results = new ArrayList<string> ();
		
		var deps_filename = Path.build_filename (Path.get_dirname (package_path), "%s.deps".printf (pkg));
		if (FileUtils.test (deps_filename, FileTest.EXISTS)) {
			try {
				string deps_content;
				ulong deps_len;
				FileUtils.get_contents (deps_filename, out deps_content, out deps_len);
				foreach (string dep in deps_content.split ("\n")) {
					dep.strip ();
					if (dep != "") {
						var deps = get_package_paths (dep, ctx, vapi_dirs);
						if (deps == null) {
							warning ("%s, dependency of %s, not found in specified Vala API directories".printf (dep, pkg));
						} else {
							foreach (string dep_package in deps) {
								results.add (dep_package);
							}
						}
					}
				}
			} catch (FileError e) {
				warning ("Unable to read dependency file: %s".printf (e.message));
			}
		}
		
		results.add (package_path);
		return results;
	}
/*
	private static bool add_package (string pkg, CodeContext context) 
	{
		if (context.has_package (pkg)) {
			// ignore multiple occurences of the same package
			return true;
		}

		Vala.List<string> packages = get_package_paths (pkg, context);
		if (packages == null) {
			return false;
		}

		context.add_package (pkg);

		foreach (string package_path in packages) {
			Utils.trace ("adding package %s: %s", pkg, package_path);
			context.add_source_file (new Vala.SourceFile (context, SourceFileType.PACKAGE, package_path));
		}
		return true;
	}
*/
	namespace Symbols
	{
		private static PredefinedSymbols _predefined = null;
		
		internal static PredefinedSymbols get_predefined ()
		{
			if (_predefined == null)
				_predefined = new PredefinedSymbols ();
				
			return _predefined;
		}
		
		public static string get_symbol_type_description (MemberType type)
		{
			switch (type) {
				case MemberType.NONE:
					return "None";
				case MemberType.VOID:
					return "Void";
				case MemberType.CONSTANT:
					return "Constant";
				case MemberType.ENUM:
					return "Enum";
				case MemberType.ENUM_VALUE:
					return "Enum Value";
				case MemberType.FIELD:
					return "Field";
				case MemberType.PROPERTY:
					return "Property";
				case MemberType.LOCAL_VARIABLE:
					return "Variable";
				case MemberType.SIGNAL:
					return "Signal";
				case MemberType.CREATION_METHOD:
					return "Creation Method";
				case MemberType.CONSTRUCTOR:
					return "Constructor";
				case MemberType.DESTRUCTOR:
					return "Destructor";
				case MemberType.METHOD:
					return "Method";
				case MemberType.DELEGATE:
					return "Delegate";
				case MemberType.PARAMETER:
					return "Parameter";
				case MemberType.ERROR_DOMAIN:
					return "Error Domain";
				case MemberType.ERROR_CODE:
					return "Error Code";
				case MemberType.NAMESPACE:
					return "Namespace";
				case MemberType.STRUCT:
					return "Struct";
				case MemberType.CLASS:
					return "Class";
				case MemberType.INTERFACE:
					return "Interface";
				case MemberType.SCOPED_CODE_NODE:
					return "Block";
				default:
					string des = type.to_string ().up ();
					warning ("Undefined description for symbol type: %s", des);
					return des;
			}
		}

		internal class PredefinedSymbols
		{
			private Symbol _connect_method;
			private Symbol _disconnect_method;
			private Symbol _signal_symbol;
			
			public DataType signal_type;
			
			public PredefinedSymbols ()
			{
				_connect_method = new Afrodite.Symbol ("connect", MemberType.METHOD);
				_connect_method.return_type = new DataType ("void");
				_connect_method.return_type.symbol =  Symbol.VOID;
				_connect_method.access = SymbolAccessibility.ANY;
				_connect_method.binding = MemberBinding.ANY;
			
				_disconnect_method = new Afrodite.Symbol ("disconnect", MemberType.METHOD);
				_disconnect_method.return_type = new DataType ("void");
				_disconnect_method.return_type.symbol =  Symbol.VOID;
				_disconnect_method.access = SymbolAccessibility.ANY;
				_disconnect_method.binding = MemberBinding.ANY;
				
				_signal_symbol = new Symbol ("#signal", MemberType.CLASS);
				_signal_symbol.add_child (_connect_method);
				_signal_symbol.add_child (_disconnect_method);
				
				signal_type = new DataType ("#signal");
				signal_type.symbol = _signal_symbol;
			}
		}
	}

	public static string unescape_xml_string (string text)
	{
		var res = text;
		return res.replace ("&lt;", "<").replace ("&gt;", ">");
	}

	internal static string binary_operator_to_string (Vala.BinaryOperator op)
	{
		string res;

		switch (op) {
			case BinaryOperator.NONE:
				res = "";
				break;
			case BinaryOperator.PLUS:
				res = "+";
				break;
			case BinaryOperator.MINUS:
				res = "-";
				break;
			case BinaryOperator.MUL:
				res = "*";
				break;
			case BinaryOperator.DIV:
				res = "/";
				break;
			case BinaryOperator.MOD:
				res = "%";
				break;
			case BinaryOperator.SHIFT_LEFT:
				res = "<<";
				break;
			case BinaryOperator.SHIFT_RIGHT:
				res = ">>";
				break;
			case BinaryOperator.LESS_THAN:
				res = "<";
				break;
			case BinaryOperator.GREATER_THAN:
				res = ">";
				break;
			case BinaryOperator.LESS_THAN_OR_EQUAL:
				res = "<=";
				break;
			case BinaryOperator.GREATER_THAN_OR_EQUAL:
				res = ">=";
				break;
			case BinaryOperator.EQUALITY:
				res = "==";
				break;
			case BinaryOperator.INEQUALITY:
				res = "!=";
				break;
			case BinaryOperator.BITWISE_AND:
				res = "&";
				break;
			case BinaryOperator.BITWISE_OR:
				res = "|";
				break;
			case BinaryOperator.BITWISE_XOR:
				res = "^";
				break;
			case BinaryOperator.AND:
				res = "&&";
				break;
			case BinaryOperator.OR:
				res = "||";
				break;
			case BinaryOperator.IN:
				res = "in";
				break;
			case BinaryOperator.COALESCE:
				res = "??";
				break;
			default:
				EnumClass cl = (EnumClass) typeof (Vala.BinaryOperator).class_ref ();
				res =  cl.get_value (op).value_nick;
				break;
		}

		return res;
	}

	internal static string unary_operator_to_string (Vala.UnaryOperator op)
	{
		string res;

		switch (op) {
			case UnaryOperator.NONE:
				res = "";
				break;
			case UnaryOperator.PLUS:
				res = "+";
				break;
			case UnaryOperator.MINUS:
				res = "-";
				break;
			case UnaryOperator.LOGICAL_NEGATION:
				res = "^";
				break;
			case UnaryOperator.BITWISE_COMPLEMENT:
				res = "~";
				break;
			case UnaryOperator.INCREMENT:
				res = "++";
				break;
			case UnaryOperator.DECREMENT:
				res = "--";
				break;
			case UnaryOperator.REF:
				res = "ref";
				break;
			case UnaryOperator.OUT:
				res = "out";
				break;
			default:
				EnumClass cl = (EnumClass) typeof (Vala.UnaryOperator).class_ref ();
				res =  cl.get_value (op).value_nick;
				break;
		}

		return res;
	}
}
