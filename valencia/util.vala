/* Copyright 2009-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Gee;

extern void qsort(void *p, size_t num, size_t size, GLib.CompareFunc func);

//// string functions ////

// Return the index of the next UTF-8 character after the character at index i.
public long next_utf8_char(string s, long i) {
    char *p = (char *) s + i;
    unowned string t = ((string) p).next_char();
    return (long) ((char *) t - (char *) s);
}

//// Helper data structures ////

class Stack<G> : GLib.Object {
    Gee.ArrayList<G> container;
    
    public Stack() {
        container = new Gee.ArrayList<G>();
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
    
    return strcmp((string) (*a_string), (string) (*b_string));
}

void make_pipe(int fd, IOFunc func) throws IOChannelError {
    IOChannel pipe = new IOChannel.unix_new(fd);
    pipe.set_flags(IOFlags.NONBLOCK);
    pipe.add_watch(IOCondition.IN | IOCondition.HUP, func);
}

