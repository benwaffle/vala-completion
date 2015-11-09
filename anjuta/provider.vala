/*
 * Copyright (C) 2008-2010 Abderrahim Kitouni
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class ValaProvider : Object, IAnjuta.Provider {
	IAnjuta.Iterable start_pos;
	weak ValaPlugin plugin;

	static Regex member_access;
	static Regex member_access_split;
	static Regex function_call;

	const string PREF_AUTOCOMPLETE_ENABLE = "completion-enable";
	const string PREF_SPACE_AFTER_FUNC = "completion-space-after-func";
	const string PREF_BRACE_AFTER_FUNC = "completion-brace-after-func";
	internal const string PREF_CALLTIP_ENABLE = "calltip-enable";

	static construct {
		try {
			member_access = new Regex("""((?:\w+(?:\s*\([^()]*\))?\.)*)(\w*)$""");
			member_access_split = new Regex ("""(\s*\([^()]*\))?\.""");
			function_call = new Regex("""(new )?((?:\w+(?:\s*\([^()]*\))?\.)*)(\w+)\s*\(([^(,)]+,)*([^(,)]*)$""");
		} catch(RegexError err) {
			critical("Regular expressions failed to compile : %s", err.message);
		}
	}

	public ValaProvider(ValaPlugin plugin) {
		this.plugin = plugin;
	}
	public unowned string get_name () throws GLib.Error {
		return "Vala";
	}
	public void populate (IAnjuta.Iterable iter) throws GLib.Error {
		if (!plugin.settings.get_boolean (PREF_AUTOCOMPLETE_ENABLE))
			return;

		var editor = plugin.current_editor as IAnjuta.EditorAssist;
		var line_start = editor.get_line_begin_position(editor.get_lineno());
		var current_text = editor.get_text(line_start, iter);

		MatchInfo match_info;
		if (! member_access.match(current_text, 0, out match_info))
			return;
		if (match_info.fetch(0).length < 2)
			return;

		start_pos = iter.clone();
		start_pos.set_position(iter.get_position() - (int) match_info.fetch(2).length);

		var names = member_access_split.split (match_info.fetch(1));

		var syms = plugin.lookup_symbol (construct_member_access (names), match_info.fetch(2),
		                                 true, plugin.get_current_context (editor) as Vala.Block);

		var proposals = new GLib.List<IAnjuta.EditorAssistProposal?>();
		foreach (var symbol in syms) {
			if (symbol is Vala.LocalVariable
			    && symbol.source_reference.begin.line > editor.get_lineno())
				continue;

			var prop = IAnjuta.EditorAssistProposal();
			prop.data = symbol;
			prop.label = symbol.name;
			proposals.prepend(prop);
		}
		proposals.reverse();
		editor.proposals(this, proposals, null, true);
	}
	public unowned IAnjuta.Iterable get_start_iter () throws GLib.Error {
		return start_pos;
	}
	public void activate (IAnjuta.Iterable iter, void* data) {
		var sym = data as Vala.Symbol;
		var editor = plugin.current_editor as IAnjuta.EditorAssist;
		var assist = sym.name;
		var is_func = false;
		var calltip = false;

		if (sym is Vala.Method || sym is Vala.Signal) {
			is_func = true;
		} else if (sym is Vala.Variable) {
			if (((Vala.Variable) sym).variable_type is Vala.DelegateType) {
				is_func = true;
			}
		}

		if (is_func) {
			if (plugin.settings.get_boolean (PREF_SPACE_AFTER_FUNC)) {
				assist += " ";
			}
			if (plugin.settings.get_boolean (PREF_BRACE_AFTER_FUNC)) {
				assist += "(";
				if (plugin.settings.get_boolean (PREF_CALLTIP_ENABLE)) {
					calltip = true;
				}
			}
		}

		(editor as IAnjuta.Document).begin_undo_action();
		editor.erase(start_pos, iter);
		editor.insert(start_pos, assist, -1);
		(editor as IAnjuta.Document).end_undo_action();

		if (calltip && editor is IAnjuta.EditorTip) {
			show_call_tip ((IAnjuta.EditorTip) editor);
		}
	}

	public void show_call_tip (IAnjuta.EditorTip editor) {
		var current_position = editor.get_position ();
		var line_start = editor.get_line_begin_position(editor.get_lineno());
		var to_complete = editor.get_text(line_start, current_position);

		List<string> tips = null;

		MatchInfo match_info;
		if (! function_call.match(to_complete, 0, out match_info))
			return;

		var creation_method = (match_info.fetch(1) != "");
		var names = member_access_split.split (match_info.fetch(2));
		var syms = plugin.lookup_symbol (construct_member_access (names), match_info.fetch(3),
		                                 false, plugin.get_current_context (editor) as Vala.Block);
		foreach (var sym in syms) {
			var calltip = new StringBuilder ();
			Vala.List<Vala.Parameter> parameters = null;
			if (sym is Vala.Method) {
				parameters = ((Vala.Method) sym).get_parameters ();
				calltip.append (((Vala.Method) sym).return_type.to_qualified_string() + " ");
			} else if (sym is Vala.Signal) {
				parameters = ((Vala.Signal) sym).get_parameters ();
			} else if (creation_method && sym is Vala.Class) {
				parameters = ((Vala.Class) sym).default_construction_method.get_parameters ();
			} else if (sym is Vala.Variable) {
				var var_type = ((Vala.Variable) sym).variable_type;
				if (var_type is Vala.DelegateType) {
					var delegate_sym = ((Vala.DelegateType) var_type).delegate_symbol;
					parameters = delegate_sym.get_parameters ();
					calltip.append (delegate_sym.return_type.to_qualified_string() + " ");
				} else {
					return;
				}
			} else {
				return;
			}

			calltip.append (sym.get_full_name ());
			calltip.append(" (");
			var prestring = "".nfill (calltip.len, ' ');
			var first = true;
			foreach (var p in parameters) {
				if(first) {
					first = false;
				} else {
					calltip.append (",\n");
					calltip.append (prestring);
				}
				if (p.ellipsis) {
					calltip.append ("...");
				} else {
					calltip.append (p.variable_type.to_qualified_string());
					calltip.append (" ").append (p.name);
				}
			}
			calltip.append (")");
			tips.append (calltip.str);
		}
		editor.show (tips, editor.get_position ());
	}
	Vala.Expression construct_member_access (string[] names) {
		Vala.Expression expr = null;

		for (var i = 0; names[i] != null; i++) {
			if (names[i] != "") {
				expr = new Vala.MemberAccess (expr, names[i]);
				if (names[i+1] != null && names[i+1].chug ().has_prefix ("(")) {
					expr = new Vala.MethodCall (expr);
					i++;
				}
			}
		}

		return expr;
	}
}
