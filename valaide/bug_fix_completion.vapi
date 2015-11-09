[CCode (cprefix = "Gtk", lower_case_cprefix = "gtk_")]
namespace Fix
{
  /* @bug https://bugzilla.gnome.org/show_bug.cgi?id=617321 */
  [CCode (cheader_filename = "gtksourceview/gtksourceview.h")]
  public interface SourceCompletionProvider : GLib.Object {
    public abstract bool activate_proposal (Gtk.SourceCompletionProposal proposal, Gtk.TextIter iter);
    public abstract Gtk.SourceCompletionActivation get_activation ();
    public abstract Gdk.Pixbuf get_icon ();
    public abstract Gtk.Widget get_info_widget (Gtk.SourceCompletionProposal proposal);
    public abstract int get_interactive_delay ();
    public abstract string get_name ();
    public abstract int get_priority ();
    public abstract bool get_start_iter (Gtk.SourceCompletionContext context, Gtk.SourceCompletionProposal proposal, Gtk.TextIter iter);
    public abstract bool match (Gtk.SourceCompletionContext context);
    public abstract void populate (Gtk.SourceCompletionContext context);
    public abstract void update_info (Gtk.SourceCompletionProposal proposal, Gtk.SourceCompletionInfo info);
  }
}

