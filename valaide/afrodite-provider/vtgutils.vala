/*
 *  vtgutils.vala - Vala developer toys for GEdit
 *  
 *  Copyright (C) 2008 - Andrea Del Signore <sejerpz@tin.it>
 *  
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *   
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *   
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330,
 *  Boston, MA 02111-1307, USA.
 */

using GLib;
using Gtk;
using Afrodite;
//using Vbf;

namespace Vtg
{
	namespace StringUtils
	{
		public static bool is_null_or_empty (string? data)
		{
			return data == null || data == "";
		}
		
		public static string replace (string data, string search, string replace) 
		{
			try {
				var regex = new GLib.Regex (GLib.Regex.escape_string (search));
				return regex.replace_literal (data, -1, 0, replace);
			} catch (GLib.RegexError e) {
				GLib.assert_not_reached ();
			}
		}
	}
	
	public class Utils : GLib.Object
	{
		private static bool _initialized = false;
		private static Gtk.SourceCompletionItem[] _proposals = null;
		//private static Vala.List<Package> _available_packages = null;
		private static Gtk.Builder _builder = null;
		private static string[] _vala_keywords = new string[] {
				"var", "out", "ref", "const",
				"static", "inline",
				"public", "protected", "private", "internal",
				"this", "base",
				"if", "while", "do", "else", "return",
				"try", "catch"
		};

		public const int prealloc_count = 500;

		public static Gdk.Pixbuf icon_generic;
		public static Gdk.Pixbuf icon_field;
		public static Gdk.Pixbuf icon_method;
		public static Gdk.Pixbuf icon_class;
		public static Gdk.Pixbuf icon_struct;
		public static Gdk.Pixbuf icon_property;
		public static Gdk.Pixbuf icon_signal;
		public static Gdk.Pixbuf icon_iface;
		public static Gdk.Pixbuf icon_const;
		public static Gdk.Pixbuf icon_enum;
		public static Gdk.Pixbuf icon_namespace;

		[Diagnostics]
		[PrintfFormat]
		internal static inline void trace (string format, ...)
		{
#if DEBUG
			var va = va_list ();
			var va2 = va_list.copy (va);
			Afrodite.Utils.log_message ("ValaToys", format, va2);
#endif
		}
	
/*		public static bool is_vala_doc (Gedit.Document doc)
		{
			return doc.language != null && doc.language.id == "vala";
		}
*/
		public static bool is_inside_comment_or_literal (SourceBuffer src, TextIter pos)
		{
			bool res = false;
			
			if (src.iter_has_context_class (pos, "comment")) {
				res = true;
			} else {
				// iter_has_context_class returns false even when
				// the cursor is in the last position of a comment|
				if (pos.is_end () || pos.get_char () == '\n') {
					if (pos.backward_char ()) {
						if (src.iter_has_context_class (pos, "comment")) {
							res = true;
						} else {
							// repos the iter
							pos.forward_char ();
						}
					}
				}
			}

			if (!res) {
				if (src.iter_has_context_class (pos, "string")) {
					if (!pos.is_start () && pos.get_char () == '"') {
						// iter_has_context_class returns true even when
						// |"the cursor is just before the string"
						if (pos.backward_char ()) {
							if (src.iter_has_context_class (pos, "string")) {
								res = true;
							} else {
								// repos the iter
								pos.forward_char ();
							}
						}
					}
				}
			}

			return res;
		}

		public static bool is_vala_keyword (string word)
		{
			bool res = false;
			foreach (string keyword in _vala_keywords) {
				if (keyword == word) {
					res = true;
					break;
				}
			}
			return res;
		}
		
		public static string get_document_name (Valide.SourceBuffer doc)
		{
			string name = doc.get_uri ();
			if (name == null) {
				name = doc.get_short_name_for_display ();
			} else {
				try {
					name = Filename.from_uri (name);
				} catch (Error e) {
					GLib.warning ("error %s converting file %s to uri", e.message, name);
				}
			}
			return name;
		}

		public static Gtk.Builder get_builder ()
		{
			if (_builder == null) {
				_builder = new Gtk.Builder ();
				try {
					_builder.add_from_file (get_ui_path ("vtg.ui"));
				} catch (Error err) {
					GLib.warning ("initialize_ui: %s", err.message);
				}
			}	
			return _builder;
		}
		
		public static unowned Gtk.SourceCompletionItem[] get_proposal_cache ()
		{
			if (!_initialized) {
				initialize ();
			}
			return _proposals;
		}

		public static string get_image_path (string id) {
			var result = Path.build_filename (Config.PIXMAPS_DIR, "symbols", "afrodite", id);
			return result;
		}

		public static string get_ui_path (string id) {
			var result = Path.build_filename (Config.DATA_DIR, "ui", id);
			return result;
		}

		private static void initialize ()
		{
			try {
				_proposals = new Gtk.SourceCompletionItem[prealloc_count];
				var _icon_generic = IconTheme.get_default().load_icon(Gtk.Stock.FILE,16,IconLookupFlags.GENERIC_FALLBACK);
				for (int idx = 0; idx < prealloc_count; idx++) {
					var obj = new Gtk.SourceCompletionItem ("", "", _icon_generic, "");
					_proposals[idx] = obj;
				}
			
				icon_generic = IconTheme.get_default().load_icon(Gtk.Stock.FILE,16,IconLookupFlags.GENERIC_FALLBACK);
				icon_field = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-field-16.png"));
				icon_method = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-method-16.png"));
				icon_class = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-class-16.png"));
				icon_struct = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-structure-16.png"));
				icon_property = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-property-16.png"));
				icon_signal = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-event-16.png"));
				icon_iface = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-interface-16.png"));
				icon_enum = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-enumeration-16.png"));
				icon_const = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-literal-16.png"));
				icon_namespace = new Gdk.Pixbuf.from_file (Utils.get_image_path ("element-namespace-16.png"));	

				_initialized = true;
			} catch (Error err) {
				warning (err.message);
			}
		}
/*
		public static Vala.List<Package> get_available_packages ()
		{
			if (_available_packages == null) {
				initialize_packages_cache ();
			}
			return _available_packages;
		}*/
/*
		private static void initialize_packages_cache ()
		{
			List<string> vapidirs = new List<string> ();
		        vapidirs.append (Config.VALA_VAPIDIR);
			vapidirs.append ("/usr/local/share/vala/vapi");

			_available_packages = new Vala.ArrayList<Package> ();

			foreach (string vapidir in vapidirs) {
				Dir dir;
				try {					      
					dir = Dir.open (vapidir);
				} catch (FileError err) {
					//do nothing
					continue;
				}
				string? filename = dir.read_name ();
				while (filename != null) {
					if (filename.has_suffix (".vapi")) {
						filename = filename.down ();
						_available_packages.add (new Package (filename.substring (0, filename.length - 5)));
					}
					filename = dir.read_name ();
				}
			}
		}*/
		
		public static Gdk.Pixbuf get_icon_for_type_name (string type_name)
		{
			if (!_initialized) {
				initialize ();
			}
			if (icon_namespace != null && type_name == "Namespace")
				return icon_namespace;
			else if (icon_class != null 
				&& (type_name == "Class" 
					|| type_name == "CreationMethod" 
					|| type_name == "Destructor" 
					|| type_name == "Constructor"
					|| type_name == "ErrorDomain"))
				return icon_class;
			else if (icon_struct != null && type_name == "Struct")
				return icon_struct;
			else if (icon_iface != null && type_name == "Interface")
				return icon_iface;
			else if (icon_field != null && type_name == "Field")
				return icon_field;
			else if (icon_property != null && type_name == "Property")
				return icon_property;
			else if (icon_method != null && (type_name == "Method" || type_name == "Delegate"))
				return icon_method;
			else if (icon_enum != null && type_name == "Enum")
				return icon_enum;
			else if (icon_const != null && (type_name == "Constant" || type_name == "EnumValue" || type_name == "ErrorCode"))
				return icon_const;
			else if (icon_signal != null && type_name == "Signal")
				return icon_signal;

			return icon_generic;
		}
/*
		public static string get_stock_id_for_target_type (Vbf.TargetTypes type)
		{
			switch (type) {
				case TargetTypes.PROGRAM:
					return Gtk.Stock.EXECUTE;
				case TargetTypes.LIBRARY:
					return Gtk.Stock.EXECUTE;
				case TargetTypes.DATA:
					return Gtk.Stock.DIRECTORY;
				case TargetTypes.BUILT_SOURCES:
					return Gtk.Stock.EXECUTE;
				default:
					return Gtk.Stock.DIRECTORY;
			}
		}
		*/
		public static int symbol_type_compare (Symbol? vala, Symbol? valb)
		{
			// why I get vala or valb with null???
			if (vala == null && valb == null)
				return 0;
			else if (vala == null && valb != null)
				return 1;
			else if (vala != null && valb == null)
				return -1;
		
			if (vala.type_name != valb.type_name) {
				if (vala.type_name == "Constant") {
					return -1;
				} else if (valb.type_name == "Constant") {
					return 1;
				} else if (vala.type_name == "Enum") {
					return -1;
				} else if (valb.type_name == "Enum") {
					return 1;										
				} else if (vala.type_name == "Field") {
					return -1;
				} else if (valb.type_name == "Field") {
					return 1;
				} else if (vala.type_name == "Property") {
					return -1;
				} else if (valb.type_name == "Property") {
					return 1;
				} else if (vala.type_name == "Signal") {
					return -1;
				} else if (valb.type_name == "Signal") {
					return 1;
				} else if (vala.type_name == "CreationMethod" 
					|| vala.type_name == "Constructor") {
					return -1;
				} else if (valb.type_name == "CreationMethod"  
					|| vala.type_name == "Constructor") {
					return 1;
				} else if (vala.type_name == "Method") {
					return -1;
				} else if (valb.type_name == "Method") {
					return 1;
				} else if (vala.type_name == "ErrorDomain") {
					return -1;
				} else if (valb.type_name == "ErrorDomain") {
					return 1;					
				} else if (vala.type_name == "Namespace") {
					return -1;
				} else if (valb.type_name == "Namespace") {
					return 1;
				} else if (vala.type_name == "Struct") {
					return -1;
				} else if (valb.type_name == "Struct") {
					return 1;					
				} else if (vala.type_name == "Class") {
					return -1;
				} else if (valb.type_name == "Class") {
					return 1;
				} else if (vala.type_name == "Interface") {
					return -1;
				} else if (valb.type_name == "Interface") {
					return 1;
				}
			}
			return GLib.strcmp (vala.name, valb.name);
		}
	}
	
	namespace ParserUtils
	{
		/**
		 * Utility method to get the text from the start iter
		 * to the end of line.
		 *
		 * @param start start iter from which start to get the text (this iter will not be modified)
		 * @return the text from the start iter to the end of line or an empty string if the iter is already on the line end.
		 */
		public static string get_line_to_end (TextIter start)
		{
			string text = "";
			
			TextIter end = start;
			end.set_line_offset (0);
			if (end.forward_to_line_end ()) {
				text = start.get_text (end);
			}
			
			return text;
		}
		
		public static void parse_line (string line, out string token, out bool is_assignment, out bool is_creation, out bool is_declaration)
		{
			token = "";
			is_assignment = false;
			is_creation = false;
			is_declaration = false;

			int i = (int)line.length - 1;
			string tok;
			int count = 0;
			token = get_token (line, ref i);
			if (token != null) {
				count = 1;
				string last_token = token;
				while ((tok = get_token (line, ref i)) != null) {
					count++;
					if (tok == "=") {
						//token = "";
						is_assignment = true;
					} else if (tok == "new") {
						//token = "";
						is_creation = true;
					}
					last_token = tok;
				}
			
				if (!is_assignment && !is_creation && count == 2) {
					if (last_token == "var" 
					    || (!Utils.is_vala_keyword (last_token) 
					        && !last_token.has_prefix ("\"") 
					        && !last_token.has_prefix ("'"))) {
						is_declaration = true;
					}
				}
				if (token.has_suffix ("."))
					token = token.substring (0, token.length - 1);
			}
			Utils.trace ("parse line new: '%s'. is_assignment: %d is_creation: %d is_declaration: %d token: '%s'", line, (int)is_assignment, (int)is_creation, (int)is_declaration, token);
		}
		
		private static string? get_token (string line, ref int i)
		{
			string tok = "";
			int skip_lev = 0;
			bool in_string = false;
			bool should_skip_spaces = true; // skip spaces on enter
			
			while (!is_eof (line, i)) {
				if (should_skip_spaces) {
					i = skip_spaces (line, i);
					should_skip_spaces = false;
				}
				
				if (!is_eof (line, i)) {
					unichar ch = line[i];
					if (skip_lev == 0) {
						if (ch == '"' || ch == '\'') {
							tok = ch.to_string () + tok;
							if (!in_string) {
								in_string = true;
							} else {
								in_string = false;
							}
						} else if (ch == '_' || ch == '.' || (tok.length == 0 && ch.isalpha ()) || (tok.length > 0 && ch.isalnum ())) {
							// valid identifier
							tok = ch.to_string () + tok;
						} else if (ch == ' ' || ch == '=' || ch == '!') {
							if (in_string) {
								tok = ch.to_string () + tok;
							} else
								break;
						}
					}

					if (!in_string) {
						if (ch == '(' || ch == '[' || ch == '{') {
							if (skip_lev > 0) {
								skip_lev--;
								if (skip_lev == 0) {
									should_skip_spaces = true; // skip the spaces before (
								}
							} else {
								break;
							}
						} else if (ch == ')' || ch == ']' || ch == '}') {
							skip_lev++;
						}
					}
					i--;
				}
			}
			
			return tok == "" ? null : tok;
		}
		
		private static int skip_spaces (string line, int i)
		{
			unichar ch = line[i];
			while (!is_eof (line, i) && (ch == ' ' || ch == '\t' || ch.isspace ())) {
				i--;
				ch = line[i];
			}
			
			return i;
		}

		private static bool is_eof (string line, int i)
		{
			return i < 0;
		}
	}
}
