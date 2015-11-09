using GLib;

namespace Tests
{
	public class Test : GLib.Object
	{
		public string field;

		public string property
		{
			owned get {
				return build_string ();
			}
		}

		public Test(string field)
		{
			this.field = field;
		}

		public string build_string ()
		{
			return "a".concat ("b");
		}

		public int do_computation (int[] array_param_int)
		{
			int result = 0;

			foreach (int param_int in array_param_int) {
				result += param_int;
			}
			return result;
		}

		public static Test factory(string param_str)
		{
			return new Test(parameter);
		}
	}

	public static void main()
	{
		var member_access_str = Test.factory (i).field.replace ("b", "c");
		var test = Test.factory ("field");
		
	}
}
