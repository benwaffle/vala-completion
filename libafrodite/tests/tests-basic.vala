using GLib;

namespace AfroditeTests
{
	public class Basic
	{
		static AfroditeTests.CompletionManager _manager;

		public static void test_this_field_string ()
		{
			var s = _manager.lookup_symbol ("this.field", 19, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.symbol_type.symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_this_property_string ()
		{
			var s = _manager.lookup_symbol ("this.property", 19, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.symbol_type.symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_this_method_invocation_int ()
		{
			var s = _manager.lookup_symbol ("this.do_computation", 19, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.symbol_type.symbol.name, Assert.Compare.EQUAL, "int");
		}

		public static void test_member_access_string ()
		{
			var s = _manager.lookup_symbol ("member_access_str", 45, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_static_factory_Test ()
		{
			var s = _manager.lookup_symbol ("test", 45, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "Test");
		}

		public static void test_static_method_param_string ()
		{
			var s = _manager.lookup_symbol ("param_str", 38, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_method_array_param_int ()
		{
			var s = _manager.lookup_symbol ("array_param_int", 28, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "int");
			// This assertion fails because in afrodite there is confusion
			// on what is a datatype and what is a symbol.
			// in the case of variable / parameters the lookup routines
			// return the symbol that resolve the type and not the type
			// Moreover the variables / parameters are datatypes and not symbols
			// all this should be fixed sooner than later
			//assert (s.children[0].symbol.return_type.is_array == true);
		}

		public static void test_method_param_int ()
		{
			var s = _manager.lookup_symbol ("result", 28, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "int");
		}

		public static void test_foreach_iterator_param_int ()
		{
			var s = _manager.lookup_symbol ("param_int", 31, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "int");
		}

		public static int main (string[] args)
		{
			Test.init (ref args);

			Test.add_func ("/afrodite/basic-test-this-field-string", test_this_field_string);
			Test.add_func ("/afrodite/basic-test-this-property-string", test_this_property_string);
			Test.add_func ("/afrodite/basic-test-this-method-invocation-int", test_this_method_invocation_int);
			Test.add_func ("/afrodite/basic-test-member-access-string", test_member_access_string);
			Test.add_func ("/afrodite/basic-test-static-factory-Test", test_static_factory_Test);
			Test.add_func ("/afrodite/basic-test-static-method-param-string", test_static_method_param_string);
			Test.add_func ("/afrodite/basic-test-method-array-param-int", test_method_array_param_int);
			Test.add_func ("/afrodite/basic-test-method-param-int", test_method_param_int);
			Test.add_func ("/afrodite/basic-test-foreach-iterator-param-int", test_foreach_iterator_param_int);

			_manager = new AfroditeTests.CompletionManager ("tests-basic-source.vala");
			_manager.parse ();

			return Test.run ();
		}
	}
}
