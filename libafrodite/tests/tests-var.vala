using GLib;

namespace AfroditeTests
{
	public class Var
	{
		static AfroditeTests.CompletionManager _manager;
		
		public static void test_simple_int ()
		{
			var s = _manager.lookup_symbol ("simple_int", 22, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "int");
		}

		public static void test_simple_string ()
		{
			var s = _manager.lookup_symbol ("simple_str", 23, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_simple_assign_string ()
		{
			var s = _manager.lookup_symbol ("simple_assign_str", 24, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_simple_assign_method_call_string ()
		{
			var s = _manager.lookup_symbol ("simple_assign_method_call_str", 25, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_simple_field_assign_double ()
		{
			var s = _manager.lookup_symbol ("simple_field_assign_dbl", 26, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "double");
		}

		public static void test_simple_method_call_1_string ()
		{
			var s = _manager.lookup_symbol ("method_call_1_str", 27, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_static_method_call_1_string ()
		{
			var s = _manager.lookup_symbol ("static_method_call_1_str", 28, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_static_method_call_3_string ()
		{
			var s = _manager.lookup_symbol ("static_method_call_3_str", 29, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "int");
		}

		public static void test_object_constructor_Test ()
		{
			var s = _manager.lookup_symbol ("object_constr_Test", 30, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "Test");
		}

		public static void test_bin_exp_simple_string ()
		{
			var s = _manager.lookup_symbol ("bin_expr_simple_str", 32, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_bin_expr_method_call_1_string ()
		{
			var s = _manager.lookup_symbol ("bin_expr_method_call_1_str", 33, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_bin_expr_method_call_2_string ()
		{
			var s = _manager.lookup_symbol ("bin_expr_method_call_2_str", 34, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_bin_exp_assign_instance_field_string ()
		{
			var s = _manager.lookup_symbol ("bin_exp_assign_instance_field_str", 35, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_if_code_block_simple_string ()
		{
			var s = _manager.lookup_symbol ("if_code_block_simple_str", 38, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static void test_if_code_block_method_call_1_string ()
		{
			var s = _manager.lookup_symbol ("if_code_block_method_call_1_str", 39, 1);
			assert (s.is_empty == false);
			Assert.cmpint (s.children.size, Assert.Compare.EQUAL, 1);
			Assert.cmpstr (s.children[0].symbol.name, Assert.Compare.EQUAL, "string");
		}

		public static int main (string[] args)
		{
			Test.init (ref args);

			Test.add_func ("/afrodite/var-test-simple-int", test_simple_int);
			Test.add_func ("/afrodite/var-test-simple-string", test_simple_string);
			Test.add_func ("/afrodite/var-test-simple-assign-string", test_simple_assign_string);
			Test.add_func ("/afrodite/var-test-simple-assign-method-call-string", test_simple_assign_method_call_string);
			Test.add_func ("/afrodite/var-test-simple-field-assign-double", test_simple_field_assign_double);
			Test.add_func ("/afrodite/var-test-simple-method-call-1-string", test_simple_method_call_1_string);
			Test.add_func ("/afrodite/var-test-static-method-call-1-string", test_static_method_call_1_string);
			Test.add_func ("/afrodite/var-test-static-method-call-3-string", test_static_method_call_3_string);
			Test.add_func ("/afrodite/var-test-object-constructor-Test", test_object_constructor_Test);
			Test.add_func ("/afrodite/var-test-bin-exp-simple-string", test_bin_exp_simple_string);
			Test.add_func ("/afrodite/var-test-bin-exp-method-call-1-string", test_bin_expr_method_call_1_string);
			Test.add_func ("/afrodite/var-test-bin-exp-method-call-2-string", test_bin_expr_method_call_2_string);
			Test.add_func ("/afrodite/var-test-bin-exp-assign-instance-field-string", test_bin_exp_assign_instance_field_string);
			Test.add_func ("/afrodite/var-test-if-code-block-simple-string", test_if_code_block_simple_string);
			Test.add_func ("/afrodite/var-test-if-code-block-method-call-1-string", test_if_code_block_method_call_1_string);

			_manager = new AfroditeTests.CompletionManager ("tests-var-source.vala");
			_manager.parse ();

			return Test.run ();
		}
	}
}
