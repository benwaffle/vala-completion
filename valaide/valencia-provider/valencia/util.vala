/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Vala;

extern void qsort(void *p, size_t num, size_t size, GLib.CompareFunc func);

//// Helper data structures ////

class Stack<G> : GLib.Object {
    Vala.ArrayList<G> container;
    
    public Stack() {
        container = new Vala.ArrayList<G>();
    }
    
    public void push(G item) {
        container.add(item);
    }

    public G top() {
        assert(container.size > 0);
        return container.get(container.size - 1);
    }

    public void pop() {
        assert(container.size > 0);
        container.remove_at(container.size - 1);
    }
    
    public int size() {
        return container.size;
    }
}

//// GLib helper functions ////

bool dir_has_parent(string dir, string parent) {
    File new_path = File.new_for_path(dir);
    while (parent != new_path.get_path()) {
        new_path = new_path.get_parent();
        
        if (new_path == null)
            return false;
    }
    
    return true;
}

int compare_string(void *a, void *b) {
    char **a_string = a;
    char **b_string = b;
    
    return strcmp(*a_string, *b_string);
}

string? filename_to_uri(string filename) {
    try {
        return Filename.to_uri(filename);
    } catch (ConvertError e) { return null; }
}

void make_pipe(int fd, IOFunc func) throws IOChannelError {
    IOChannel pipe = new IOChannel.unix_new(fd);
    pipe.set_flags(IOFlags.NONBLOCK);
    pipe.add_watch(IOCondition.IN | IOCondition.HUP, func);
}

// a workaround for bug https://bugzilla.gnome.org/show_bug.cgi?id=595885 in Vala 0.7.6
void idle_add(SourceFunc function, int priority = Priority.DEFAULT_IDLE) {
    Idle.add_full(priority, function);
}

