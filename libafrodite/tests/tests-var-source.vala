using GLib;

namespace Tests
{
	public static string static_string_method (int value)
	{
		return "";
	}

	public class Test
	{
		public double field;

		public string string_method (int value)
		{
			return "";
		}

		public void test ()
		{
			var simple_int = 1;
			var simple_str = "Test";
			var simple_assign_str = simple_str; 
			var simple_assign_method_call_str = simple_str.replace ("a", "B"); 
			var simple_field_assign_dbl = field;
			var method_call_1_str = string_method (10);
			var static_method_call_1_str = static_string_method (10);
			var static_method_call_3_str = static_string_method (10).replace ("a","B").to_int ();
			var object_constr_Test = new Test ();

			var bin_expr_simple_str = "Hello" + " " + "Word";
			var bin_expr_method_call_1_str = "Hello" + string_method (10) + "Word";
			var bin_expr_method_call_2_str = "Hello" + string_method (10).replace ("a", "B") + "Word";
			var bin_exp_assign_instance_field_str = "A" + "B" + object_constr_Test.field.to_string () + "C" + "D";
			
			if (true) {
				var if_code_block_simple_str = "Test";
				var if_code_block_method_call_1_str = this.string_method (20);
			}
		}
	}
}
