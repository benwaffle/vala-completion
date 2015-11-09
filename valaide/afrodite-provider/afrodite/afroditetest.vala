/* afroditetest.vala
 *
 * Copyright (C) 2010  Andrea Del Signore
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
using Afrodite;

string option_symbol_name;
int option_line;
int option_column;
string option_visible_symbols;
string option_filter;
string option_namespace;
[NoArrayLength ()]
string[] option_files;
int option_repeat;
bool option_live_buffers;

const OptionEntry[] options = {
	{ "symbol-name", 's', 0, OptionArg.STRING, ref option_symbol_name, "Symbol to search NAME", "NAME" },
	{ "visible-symbols", 'd', 0, OptionArg.FILENAME, ref option_visible_symbols, "Dump visible symbols from line / column of source FILENAME", "FILENAME" },
	{ "filter", 'f', 0, OptionArg.STRING, ref option_filter, "Filter results showing only symbols starting with NAME", "NAME" },
	{ "line", 'l', 0, OptionArg.INT, ref option_line, "Line NUMBER", "NUMBER" },
	{ "column", 'c', 0, OptionArg.INT, ref option_column, "Column NUMBER", "NUMBER" },
	{ "repeat", 'r', 0, OptionArg.INT, ref option_repeat, "Repeat parsing NUMBER", "NUMBER" },
	{ "dump-namespace", 'n', 0, OptionArg.STRING, ref option_namespace, "Namespace to dump NAME", "NAME" },
	{ "queue-as-live-buffer", 'e', 0, OptionArg.STRING, ref option_live_buffers, "Parse the source files as live buffers", null },
	{ "", 0, 0, OptionArg.FILENAME_ARRAY, ref option_files, "Source files NAME", "NAME" },
	{ null }
};

public class AfroditeTest.Application : Object {

	private MainLoop _loop;
	private Afrodite.CompletionEngine _engine;
	
	public int run (string[] args) {
		// parse options
		var opt_context = new OptionContext ("- Afrodite Test");
		opt_context.set_help_enabled (true);
		opt_context.add_main_entries (options, null);
		try {
			opt_context.parse (ref args);
		} catch (Error err) {
			error (_("parsing options"));
		}

		if (option_repeat == 0)
			option_repeat = 1;

		parse ();
		_loop = new MainLoop();
		_loop.run();
		return 0;
	}

	private void on_begin_parsing (CompletionEngine engine)
	{
		print ("\nAfrodite engine is parsing sources\n");
	}
	private void on_end_parsing (CompletionEngine engine)
	{
		print ("\nAfrodite engine end parsing sources\n");
		_loop.quit ();
		dump (engine);
	}

	private void dump (CompletionEngine engine)
	{
		print (": done\n\n");
		print ("Looking for '%s' %d,%d\n\nDump follows:\n", option_symbol_name, option_line, option_column);
		while (true)
		{
			// dumping tree (just a debug facility)
			var dumper = new Afrodite.AstDumper ();
			dumper.dump (engine.ast, option_namespace);
			print ("\n");

			// Query the AST
			if (option_visible_symbols != null) {
				var source = engine.ast.lookup_source_file (option_visible_symbols);
				if (source != null) {
					// get the source node at this position
					var s = engine.ast.get_symbol_for_source_and_position (source, option_line, option_column);
					if (s != null) {
						Vala.List<Symbol> syms = null;
						syms = engine.ast.lookup_visible_symbols_from_symbol (s, option_filter);
						print ("Symbols found: %d\n", syms.size);
						foreach (Symbol sym in syms) {
							print ("          from %s: %s\n", sym.parent == null ? "<root>" : sym.parent.fully_qualified_name, Utils.unescape_xml_string (sym.description));
						}
					} else {
						print ("no symbol found for position: %d-%d\n", option_line, option_column);
					}
				} else {
					print ("source file not found: %s\n", option_visible_symbols);
				}
			} else if (option_symbol_name != null) {
				// Setup query options
				QueryOptions options = QueryOptions.standard ();
				options.auto_member_binding_mode = true;
				options.compare_mode = CompareMode.EXACT;
				options.access = Afrodite.SymbolAccessibility.ANY;
				options.binding = Afrodite.MemberBinding.ANY;

				QueryResult sym = null;
				sym = engine.ast.get_symbol_type_for_name_and_path (options, option_symbol_name, option_files[0], option_line, option_column);
				print ("The type for '%s' is: ", option_symbol_name);
				if (!sym.is_empty) {
					foreach (ResultItem item in sym.children) {
						print ("%s\n     Childs:\n", Utils.unescape_xml_string (item.symbol.description));
						if (item.symbol.has_children) {
							int count = 0;
							// print an excerpt of the child symbols
							foreach (var child in item.symbol.children) {
								print ("          %s\n", Utils.unescape_xml_string (child.description));
								count++;
								if (count == 6) {
									print ("          ......\n");
									break;
								}
							}
							if (count < 6 && item.symbol.has_base_types) {
								foreach (var base_item in item.symbol.base_types) {
									if (base_item.unresolved || !base_item.symbol.has_children)
										continue;

									foreach (var child in base_item.symbol.children) {
										print ("          %s\n", Utils.unescape_xml_string (child.description));
										count++;
										if (count == 6)
											break;
									}

									if (count == 6) {
										print ("          ......\n");
										break;
									}
								}
							}
						}
					}
				} else {
					print ("unresolved :(\n");
				}
			}
			break;
		}
		
		print ("done\n");
	}
	
	private void parse () {
		int i = 0;

		_engine = new Afrodite.CompletionEngine ("afrodite-test-engine");
		_engine.begin_parsing.connect (this.on_begin_parsing);
		_engine.end_parsing.connect (this.on_end_parsing);
		
		for(int repeat = 0; repeat < option_repeat; repeat++) {
			print ("Adding sources (%d):\n", repeat);
			i = 0;
			while (option_files[i] != null) {
				string filename = option_files[i];
				print ("   %s%s\n", filename, option_live_buffers ? " (live buffer)" : "");
				if (option_live_buffers) {
					var source = new Afrodite.SourceItem ();
					string buffer;
					try {
						FileUtils.get_contents(filename, out buffer);
					} catch (Error err) {
						error (_("parsing options"));
					}
					source.content = buffer;
					source.path = "live-buffer.vala";
					_engine.queue_source (source);
				} else {
					_engine.queue_sourcefile (filename);
				}
				i++;
			}
		}
	}

	static int main (string[] args) {
		var application = new Application ();
		return application.run (args);
	}
}
