namespace Assert
{
	public enum Compare
	{
		[CCode (cname="==")]
		EQUAL,

		[CCode (cname="!=")]
		NOT_EQUAL
	}
	
	[CCode (cname="g_assert_cmpstr")]
	public bool cmpstr (string a, Compare operator, string b);
	
	[CCode (cname="g_assert_cmpint")]
	public bool cmpint (int a, Compare operator, int b);

}

