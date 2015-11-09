using GLib;

namespace AfroditeTests
{
	public class Integrity
	{
		static AfroditeTests.CompletionManager _manager;

		public static void test_source_remove ()
		{
			var codedom = _manager.engine.codedom;
			var source = codedom.lookup_source_file (_manager.filename);

			assert (source != null);

			// DEBUG: copy the symbol table for future reference
			var symbol_table = new GLib.HashTable <weak void*, string> (GLib.direct_hash, GLib.direct_equal);
			foreach (unowned Afrodite.Symbol symbol in codedom.symbols.get_values ()) {
				symbol_table.insert (symbol, symbol.fully_qualified_name);
			}

			// DEBUG: copy of the source symbol table
			var file_symbol_table = new GLib.HashTable <weak void*, string> (GLib.direct_hash, GLib.direct_equal);
			foreach (unowned Afrodite.Symbol symbol in source.symbols) {
				file_symbol_table.insert (symbol, symbol.fully_qualified_name);
			}

			// remove the source
			_manager.remove_source ();

			// do the integrity test
			source = codedom.lookup_source_file (_manager.filename);
			assert ( source == null );

			// all the source symbols should be disposed
			foreach (weak void* key in file_symbol_table.get_keys ()) {
				var symbol = (Afrodite.Symbol*) key;
				if (symbol is GLib.Object) {
					error ("symbol leaked: %p %s", key, file_symbol_table.lookup (key));
				} else {
					message ("symbol checked: %p %s. destroyed --> OK", key, file_symbol_table.lookup (key));
				}
			}

			// the ast should not contain a disposed symbol
			// and all the symbol should have just one source reference
			// and that reference shouldn't be my source file
			foreach (unowned Afrodite.Symbol symbol in codedom.symbols.get_values ()) {
				if (!(symbol is GLib.Object)) {
					error ("symbol disposed: %p %s", symbol, symbol_table.lookup (symbol));
				}
				Assert.cmpint ((int) symbol.has_source_references, Assert.Compare.EQUAL, (int)true);
				var sr = symbol.lookup_source_reference_filename (_manager.filename);
				assert (sr == null);
			}
		}

		public static int main (string[] args)
		{
			Test.init (ref args);

			Test.add_func ("/afrodite/integrity-test-source-remove", test_source_remove);

			_manager = new AfroditeTests.CompletionManager ("tests-basic-source.vala");
			_manager.parse ();
			
			return Test.run ();
		}
	}
}
