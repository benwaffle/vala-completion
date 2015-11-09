
namespace Reflection
{
	[CCode (cname = "G_TYPE_FROM_INSTANCE")]
	public static GLib.Type get_type_from_instance (void* typeinstance);
}

namespace Posix.Processes
{
	[CCode (cname = "kill", cheader_filename = "signal.h,sys/types.h")]
	public static int kill (int pid, int sig);
}

namespace GLib
{
	[CCode (cname = "g_strcmp0")]
	public static int strcmp0 (string vala, string valb);
}