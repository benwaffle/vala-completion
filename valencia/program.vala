/* Copyright 2009-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Gee;

namespace Valencia {

public class SymbolSet : Object {
    // Since the set stores Symbols, but we actually want to hash their (name) strings, we must
    // provide custom hash and equality functions
    HashSet<Symbol> symbols = 
        new HashSet<Symbol>(Symbol.hash, Symbol.equal);
    string name;
    bool exact;
    bool type;
    bool constructor;
    bool local_symbols;

    public SymbolSet(string name, bool type, bool exact, bool constructor, bool local_symbols) {
        this.name = exact ? name : name.down(); // case-insensitive matching
        this.type = type;
        this.exact = exact;
        this.constructor = constructor;
        this.local_symbols = local_symbols;
    }

    public SymbolSet.empty() {
        name = "";
        type = false;
        exact = false;
        constructor = false;
        local_symbols = false;
    }

    void add_constructor(Symbol sym) {
        Class c = sym as Class;
        if (c != null) {
            if (exact) {
                Symbol? s = c.lookup_constructor();
                if (s != null)
                    symbols.add(s);
            } else {
                // Recursively add subclass constructors to the set
                foreach (Node n in c.members) {
                    Class subclass = n as Class;
                    if (subclass != null)
                        add_constructor(subclass);
                    else if (n is Constructor)
                        symbols.add((Symbol) n);
                }
            }
            // Recursively add subclass constructors to the set
        } else if (sym is Constructor) {
            symbols.add(sym);
        }
    }

    public bool add(Symbol sym) {
        if (sym.name == null)
            return false;

        // Case-insensitive matching for inexact matching
        if (exact) {
            if (sym.name != name)
                return false;
        } else if (!sym.name.down().has_prefix(name)) {
                return false;
        }

        if (type && sym as TypeSymbol == null)
            return false;

        if (constructor) {
            add_constructor(sym);
        // Don't add constructors to non-constructor sets
        } else if (!(sym is Constructor))
            symbols.add(sym);

        return exact;
    }

    // Convenience function for getting the first element without having to use iterators.
    // This is mostly for users expecting exact matches.
    public Symbol? first() {
        foreach (Symbol s in symbols)
            return s;
        return null;
    }

    public unowned HashSet<Symbol>? get_symbols() {
        // It doesn't make sense to display the exact match of a partial search if there is only
        // one symbol found that matches perfectly (only for autocomplete!)
        if (symbols.size == 0 || (symbols.size == 1 && !exact && !local_symbols &&
            first().name == name))
            return null;

        return symbols;
    }
    
    public string get_name() {
        return name;
    }
    
    public Symbol? get_symbol(string name) {
        foreach (Symbol symbol in symbols) {
            if (symbol.name == name)
                return symbol;
        }
        return null;
    }
    
    public bool local_symbols_only() {
        return local_symbols;
    }
}

public abstract class Node : Object {
    public int start;
    public int end;

    Node(int start, int end) {
        this.start = start;
        this.end = end;
    }

    // Return all children which may possibly contain a scope.
    public virtual ArrayList<Node>? children() { return null; }
    
    protected static ArrayList<Node>? single_node(Node? n) {
        if (n == null)
            return null;
        ArrayList<Node> a = new ArrayList<Node>();
        a.add(n);
        return a;
    }
    
    public Chain? find(Chain? parent, int pos) {
        Chain c = parent;
        Scope s = this as Scope;
        if (s != null)
            c = new Chain(s, parent);    // link this scope in
            
        ArrayList<Node> nodes = children();
        if (nodes != null)
            foreach (Node n in nodes)
                if (n.start <= pos && pos <= n.end)
                    return n.find(c, pos);
        return c;
    }

    public static bool lookup_in_array(ArrayList<Node> a, SymbolSet symbols) {
        foreach (Node n in a) {
            Symbol s = n as Symbol;
            if (s != null && symbols.add(s))
                return true;
        }
        return false;
    }
    
    public abstract void print(int level);

    protected void do_print(int level, string s) {
        stdout.printf("%s%s\n", string.nfill(level * 2, ' '), s);
    }    
}

public abstract class Symbol : Node {
    public SourceFile source;
    public string name;        // symbol name, or null for a constructor
    
    public Symbol(string? name, SourceFile source, int start, int end) {
        base(start, end);
        this.source = source;
        this.name = name;
    }
    
    protected void print_name(int level, string s) {
        do_print(level, s + " " + name);
    }
    
    public int name_length() {
        int length = 0;
        // Since unnamed constructors' names are null, just use the parent class' name
        if (name == null) {
            if (this is Constructor) {
                Constructor c = (Constructor) this;
                length = (int) c.parent.name.length;
            }
        } else {
            length = (int) name.length;
        }
        return length;
    }

    public static uint hash(Symbol symbol) {
        // Unnamed constructors always have null names, so hash their parent class' name
        if (symbol.name == null) {
            Constructor c = symbol as Constructor;
            assert(c != null);
            return c.parent.name.hash();
        } else return symbol.name.hash();
    }

    public static bool equal(Symbol a_symbol, Symbol b_symbol) {
        return a_symbol.name == b_symbol.name;
    }
}

public interface Scope : Object {
    // Adds all members not past the position specified by 'pos' inside this scope to 'symbols'
    // (members meaning fields, methods, classes, enums, etc...)
    public abstract bool lookup(SymbolSet symbols, int pos);
}

public abstract class TypeSymbol : Symbol {
    public TypeSymbol(string? name, SourceFile source, int start, int end) {
        base(name, source, start, end);
    }
}

public abstract class Statement : Node {
    public Statement(int start, int end) { base(start, end); }
    
    public virtual bool defines_symbol(SymbolSet symbols) { return false; }
}

public abstract class Variable : Symbol {
    public Expression type;
    
    public Variable(Expression type, string name, SourceFile source, int start, int end) {
        base(name, source, start, end);
        this.type = type;
    }
    
    protected abstract string kind();
    
    public override void print(int level) {
        print_name(level, kind() + " " + type.to_string());
    }
}

public class LocalVariable : Variable {
    public LocalVariable(Expression type, string name, SourceFile source, int start, int end) {
        base(type, name, source, start, end);
    }
    
    protected override string kind() { return "local"; }
}

public class DeclarationStatement : Statement {
    public ArrayList<LocalVariable> variables;
    
    public DeclarationStatement(ArrayList<LocalVariable> variables, int start, int end) {
        base(start, end);
        this.variables = variables;
    }

    public override bool defines_symbol(SymbolSet symbols) {
        foreach (LocalVariable variable in variables)
            if (symbols.add(variable))
                return true;
        return false;
    }
    
    public override void print(int level) {
        foreach (LocalVariable variable in variables)
            variable.print(level);
    }
}

// The For class will handle both for and foreach statements
class For : Statement, Scope {
    public DeclarationStatement declaration;
    public Statement statement;
    
    public For(DeclarationStatement declaration, Statement? statement, int start, int end) {
        base(start, end);
        this.declaration = declaration;
        this.statement = statement;
    }
    
    public override ArrayList<Node>? children() { return single_node(statement); }
    
    bool lookup(SymbolSet symbols, int pos) {
        return declaration.defines_symbol(symbols);
    }    

    protected override void print(int level) {
        do_print(level, "foreach");
        
        foreach (LocalVariable variable in declaration.variables) {
            variable.print(level + 1);
            if (statement != null)
                statement.print(level + 1);
        }
    }
}

public class Chain : Object {
    Scope scope;
    Chain parent;
    
    public Chain(Scope scope, Chain? parent) {
        this.scope = scope;
        this.parent = parent;
    }
    
    public void lookup(SymbolSet symbols, int pos) {
        if (scope.lookup(symbols, pos))
            return;

        if (parent != null)
            parent.lookup(symbols, pos);
    }
    
    // Returns the symbol of the first parent class it finds
    public Symbol? lookup_this() {
        if (parent == null)
            return null;
    
        if (parent.scope is Class) {
            return (Symbol) parent.scope;
        }

        return parent.lookup_this();
    }

    // Returns the symbol of the base class of the parent class
    public Symbol? lookup_base(SourceFile sf) {
        Class? parent_class = (Class) lookup_this();
        if (parent_class == null)
            return null;
        
        foreach (Expression base_name in parent_class.super) {
            Symbol base_class = sf.resolve_type(base_name, parent_class.start - 1);
            if (base_class != null && !(base_class is Interface)) {
                return base_class;
            }
        }

        return null;
    }
}

public class Block : Statement, Scope {
    public ArrayList<Statement> statements = new ArrayList<Statement>();

    public override ArrayList<Node>? children() { return statements; }
    
    public Block() {
        base(0, 0);     // caller will fill in start and end later
    }
    
    bool lookup(SymbolSet symbols, int pos) {
        foreach (Statement s in statements) {
            if (s.start > pos)
                return false;
            if (s.defines_symbol(symbols))
                return true;
        }
        return false;
    }
    
    protected override void print(int level) {
        do_print(level, "block");
        
        foreach (Statement s in statements)
            s.print(level + 1);
    }
  }

  public class Parameter : Variable {
    public Parameter(Expression type, string name, SourceFile source, int start, int end) {
        base(type, name, source, start, end);
    }
    
    protected override string kind() { return "parameter"; }
}

// a construct block
public class Construct : Node {
    public Block body;
    
    public Construct(Block body, int start, int end) {
        base(start, end);
        this.body = body;
    }
    
    public override ArrayList<Node>? children() {
        return single_node(body);
    }

    public override void print(int level) {
        do_print(level, "construct");
        if (body != null)
            body.print(level + 1);
    }
}

public class Method : Symbol, Scope {
    public ArrayList<Parameter> parameters = new ArrayList<Parameter>();
    public Expression return_type;
    public Block body;
    string prototype = "";

    public Method(string? name, Expression? return_type, SourceFile source) { 
        base(name, source, 0, 0); 
        this.return_type = return_type;
    }
    
    public override ArrayList<Node>? children() { return single_node(body);    }
    bool lookup(SymbolSet symbols, int pos) {
        return Node.lookup_in_array(parameters, symbols);
    }
    
    protected virtual void print_type(int level) {
        print_name(level, "method");
    }
    
    public override void print(int level) {
        print_type(level);
        
        foreach (Parameter p in parameters)
            p.print(level + 1);
        if (body != null)
            body.print(level + 1);
    }
    
    public void update_prototype(string proto) {
        prototype = proto;
        prototype.chomp();

        // Clean up newlines and remove extra spaces
        if (prototype.contains("\n")) {
            string[] split_lines = prototype.split("\n");
            prototype = "";
            for (int i = 0; split_lines[i] != null; ++i) {
                weak string str = split_lines[i];
                str.strip();
                prototype += str;
                if (split_lines[i + 1] != null)
                    prototype += " ";
            }
        }
    }
    
    public string to_string() {
        return prototype;
    }
    
}

// We use the name "VSignal" to avoid a name conflict with GLib.Signal.
public class VSignal : Method {
    public VSignal(string? name, Expression return_type, SourceFile source) {
        base(name, return_type, source);
    }
}

public class Delegate : Method {
    public Delegate(string? name, Expression return_type, SourceFile source) {
        base(name, return_type, source);
    }
}

public class Constructor : Method {
    public weak Class parent;

    public Constructor(string? unqualified_name, Class parent, SourceFile source) { 
        base(unqualified_name, null, source); 
        this.parent = parent;
    }
    
    public override void print_type(int level) {
        do_print(level, "constructor");
    }
}

public class Field : Variable {
    public Field(Expression type, string name, SourceFile source, int start, int end) {
        base(type, name, source, start, end);
    }
    
    protected override string kind() { return "field"; }
}

public class Property : Variable {
    // A Block containing property getters and/or setters.
    public Block body;

    public Property(Expression type, string name, SourceFile source, int start, int end) {
        base(type, name, source, start, end);
    }
    
    public override ArrayList<Node>? children() {
        return single_node(body);
    }

    protected override string kind() { return "property"; }

    public override void print(int level) {
        base.print(level);
        body.print(level + 1);
    }
}

// a class, struct, interface or enum
public class Class : TypeSymbol, Scope {
    public ArrayList<Expression> super = new ArrayList<Expression>();
    public ArrayList<Node> members = new ArrayList<Node>();
    weak Class enclosing_class;

    public Class(string name, SourceFile source, Class? enclosing_class) {
        base(name, source, 0, 0); 
        this.enclosing_class = enclosing_class;
    }
    
    public override ArrayList<Node>? children() { return members; }
    
    public Symbol? lookup_constructor() {
        foreach (Node n in members) {
            Constructor c = n as Constructor;
            // Don't accept named constructors
            if (c != null && c.name == null) {
                return (Symbol) c;
            }
        }
        return null;
    }
    
    bool lookup1(SymbolSet symbols, HashSet<Class> seen) {
        if (Node.lookup_in_array(members, symbols))
            return true;

        // Make sure we don't run into an infinite loop if a user makes this mistake:
        // class Foo : Foo { ...
        seen.add(this);

        // look in superclasses        
        foreach (Expression s in super) {
            // We look up the parent class in the scope at (start - 1); that excludes
            // this class itself (but will include the containing sourcefile,
            // even if start == 0.)
            Class c = source.resolve_type(s, start - 1) as Class;

            if (c != null && !seen.contains(c)) {
                if (c.lookup1(symbols, seen))
                    return true;
            }
        }
        return false;
        
    }    
    
    bool lookup(SymbolSet symbols, int pos) {
        return lookup1(symbols, new HashSet<Class>());
    }
    
    public override void print(int level) {
        StringBuilder sb = new StringBuilder();
        sb.append("class " + name);
        for (int i = 0 ; i < super.size ; ++i) {
            sb.append(i == 0 ? " : " : ", ");
            sb.append(super.get(i).to_string());
        }
        do_print(level, sb.str);
        
        foreach (Node n in members)
            n.print(level + 1);
    }

    public string to_string() {
        return (enclosing_class != null) ? enclosing_class.to_string() + "." + name : name;
    }
}

public class Interface : Class {
    public Interface(string name, SourceFile source, Class? enclosing_class) {
        base(name, source, enclosing_class);
    }
}

// A Namespace is a TypeSymbol since namespaces can be used in type names.
public class Namespace : TypeSymbol, Scope {
    public string full_name;
    
    public Namespace(string? name, string? full_name, SourceFile source) {
        base(name, source, 0, 0);
        this.full_name = full_name;
    }
    
    public ArrayList<Symbol> symbols = new ArrayList<Symbol>();
    
    public override ArrayList<Node>? children() { return symbols; }

    public bool lookup(SymbolSet symbols, int pos) {
        return source.program.lookup_in_namespace(full_name, symbols);
    }
    
    public bool lookup1(SymbolSet symbols) {
        return Node.lookup_in_array(this.symbols, symbols);
    }
    
    public void lookup_all_toplevel_symbols(SymbolSet symbols) {
        foreach (Symbol s in this.symbols) {
            if (s is Namespace) {
                Namespace n = (Namespace) s;
                n.lookup_all_toplevel_symbols(symbols);
            } else {
                symbols.add(s);
            }
        }
    }

    public override void print(int level) {
        print_name(level, "namespace");
        foreach (Symbol s in symbols)
            s.print(level + 1);
    }
}

public class SourceFile : Node, Scope {
    public weak Program program;
    public string filename;
    
    ArrayList<string> using_namespaces = new ArrayList<string>();
    public ArrayList<Namespace> namespaces = new ArrayList<Namespace>();
    public Namespace top;
    
    public SourceFile(Program? program, string filename) {
        base(0, 0);
        this.program = program;
        this.filename = filename;
        alloc_top();
    }

    void alloc_top() {
        top = new Namespace(null, null, this);
        namespaces.add(top);
        using_namespaces.add("GLib");
    }

    public void clear() {
        using_namespaces.clear();
        namespaces.clear();
        alloc_top();
    }

    public override ArrayList<Node>? children() { return single_node(top); }

    public void add_using_namespace(string name) {
        // Make sure there isn't a duplicate, since GLib is always added
        if (name == "GLib")
            return;
        using_namespaces.add(name);
    }

    bool lookup(SymbolSet symbols, int pos) {
        foreach (string ns in using_namespaces) {
            if (program.lookup_in_namespace(ns, symbols))
                return true;
        }
        return false;
    }

    public bool lookup_in_namespace(string? namespace_name, SymbolSet symbols) {
        foreach (Namespace n in namespaces)
            if (n.full_name == namespace_name) {
                if (symbols.local_symbols_only())
                    n.lookup_all_toplevel_symbols(symbols);
                else if (n.lookup1(symbols))
                    return true;
            }
        return false;
    }

    public SymbolSet resolve_non_compound(Expression name, Chain chain, int pos, bool find_type,
                                          bool exact, bool constructor, bool local_symbols) {
        Symbol s;
        SymbolSet symbols;
        
        if (name is This) {
            s = chain.lookup_this();
        } else if (name is Base) {
            s = chain.lookup_base(this);
        } else if (name is MethodCall) {
            // First find the method symbol... (doesn't support constructors yet)
            MethodCall method_call = (MethodCall) name;
            symbols = resolve1(method_call.method, chain, pos, false, exact, false, local_symbols);
            s = symbols.first();
            
            Constructor c = s as Constructor;
            if (c != null)
                s = c.parent;
            else {
                Method m = s as Method;
                if (m != null)
                    // find the return type symbol of the method
                    return resolve1(m.return_type, find(null, m.start), m.start, true, exact, false, local_symbols);
                return new SymbolSet.empty();
            }
        } else if (name is Id) {
            Id id = (Id) name;
            symbols = new SymbolSet(id.name, find_type, exact, constructor, local_symbols);
            chain.lookup(symbols, pos);
            return symbols;        
        } else {    // name is New
            New n = (New) name;
            return resolve1(n.class_name, chain, pos, find_type, exact, true, local_symbols);
        }

        if (s != null) {
            symbols = new SymbolSet(s.name, find_type, true, constructor, local_symbols);
            symbols.add(s);
        } else symbols = new SymbolSet.empty();  // return an "empty" set
        
        return symbols;
    }

    public SymbolSet resolve1(Expression name, Chain chain, int pos, bool find_type, bool exact, 
                              bool constructor, bool local_symbols) {
        if (!(name is CompoundExpression)) {
            return resolve_non_compound(name, chain, pos, find_type, exact, constructor, local_symbols);
        }

        // The basename of a qualified name is always going to be an exact match, and never a
        // constructor
        CompoundExpression compound = (CompoundExpression) name;
        SymbolSet left_set = resolve1(compound.left, chain, pos, find_type, true, false, local_symbols);
        Symbol left = left_set.first();
        if (!find_type) {
            Variable v = left as Variable;
            if (v != null) {
                left = v.source.resolve_type(v.type, v.start);
            }
        }
        Scope scope = left as Scope;

        // It doesn't make sense to be looking up members of a method as a qualified name
        if (scope is Method)
            return new SymbolSet.empty();

        SymbolSet symbols = new SymbolSet(compound.right, find_type, exact, constructor, local_symbols);
        if (scope != null)
            scope.lookup(symbols, 0);

        return symbols;
    }

    public Symbol? resolve(Expression name, int pos, bool constructor) {
        SymbolSet symbols = resolve1(name, find(null, pos), pos, false, true, constructor, false);
        return symbols.first();
    }    

    public Symbol? resolve_type(Expression type, int pos) {
        SymbolSet symbols = resolve1(type, find(null, pos), 0, true, true, false, false);
        return symbols.first();
    }

    public SymbolSet resolve_prefix(Expression prefix, int pos, bool constructor) {
        return resolve1(prefix, find(null, pos), pos, false, false, constructor, false);
    }
    
    public SymbolSet resolve_all_locals(Expression prefix, int pos) {
        return resolve1(prefix, find(null, pos), pos, false, false, false, true);
    }
    
    public Symbol? resolve_local(Expression name, int pos) {
        SymbolSet symbols = resolve1(name, find(null, pos), pos, false, true, false, true);
        return symbols.first();
    }

    public override void print(int level) {
        top.print(level);
    }
}

public class ErrorInfo : Object {
    public string filename;
    public string start_line;
    public string start_char;
    public string end_line;
    public string end_char;
}

public class ErrorPair : Object {
    public Gtk.TextMark document_pane_error;
    public Gtk.TextMark build_pane_error;
    public ErrorInfo error_info;
    
    public ErrorPair(Gtk.TextMark document_err, Gtk.TextMark build_err, ErrorInfo err_info) {
        document_pane_error = document_err;
        build_pane_error = build_err;
        error_info = err_info;
    }
}

public class ErrorList : Object {
    public Gee.ArrayList<ErrorPair> errors;
    public int error_index;
    
    public ErrorList() {
        errors = new Gee.ArrayList<ErrorPair>();
        error_index = -1;    
    }
}

public class Makefile : Object {
    public string path;
    public string relative_binary_run_path;
    
    bool regex_parse(GLib.DataInputStream datastream) {
        Regex program_regex, rule_regex, root_regex;
        try {            
            root_regex = new Regex("""^\s*BUILD_ROOT\s*=\s*1\s*$""");
            program_regex = new Regex("""^\s*PROGRAM\s*=\s*(\S+)\s*$""");
            rule_regex = new Regex("""^ *([^: ]+) *:""");
        } catch (RegexError e) {
            GLib.warning("A RegexError occured when creating a new regular expression.\n");
            return false;        // TODO: report error
        }

        bool rule_matched = false;
        bool program_matched = false;
        bool root_matched = false;
        MatchInfo info;

        // this line is necessary because of a vala compiler bug that thinks info is uninitialized
        // within the block: if (!program_matched && program_regex.match(line, 0, out info)) {
        program_regex.match(" ", 0, out info);
            
        while (true) {
            size_t length;
            string line;
           
            try {
                line = datastream.read_line(out length, null);
            } catch (GLib.Error err) {
                GLib.warning("An unexpected error occurred while parsing the Makefile.\n");
                return false;
            }
            
            // The end of the document was reached, ending...
            if (line == null)
                break;
            
            if (!program_matched && program_regex.match(line, 0, out info)) {
                // The 'PROGRAM = xyz' regex can be matched anywhere in the makefile, where the rule
                // regex can only be matched the first time.
                relative_binary_run_path = info.fetch(1);
                program_matched = true;
            } else if (!rule_matched && !program_matched && rule_regex.match(line, 0, out info)) {
                rule_matched = true;
                relative_binary_run_path = info.fetch(1);
            } else if (!root_matched && root_regex.match(line, 0, out info)) {
                root_matched = true;
            }

            if (program_matched && root_matched)
                break;
        }
        
        return root_matched;
    }
    
    // Return: true if current directory will be root, false if not
    public bool parse(GLib.File makefile) {
        GLib.FileInputStream stream;
        try {
            stream = makefile.read(null);
         } catch (GLib.Error err) {
            GLib.warning("Unable to open %s for parsing.\n", path);
            return false;
         }
        GLib.DataInputStream datastream = new GLib.DataInputStream(stream);
        
        return regex_parse(datastream);
    }

    public void reparse() {
        if (path == null)
            return;
            
        GLib.File makefile = GLib.File.new_for_path(path);
        parse(makefile);
    }
    
    public void reset_paths() {
        path = null;
        relative_binary_run_path = null;
    }

}

public class ConfigurationFile : Object {
    weak Program parent_program;

    const string version_keyword = "version";
    const string version = "1";
    const string build_command_keyword = "build_command";
    const string clean_command_keyword = "clean_command";
    const string default_build_command = "make";
    const string default_clean_command = "make clean";
    const string pkg_blacklist_keyword = "pkg_blacklist";
    const string default_pkg_blacklist = "";

    string build_command;
    string clean_command;
    string pkg_blacklist;
    string[]? blacklisted_vapis = null;

    enum MatchValue {
        MATCHED,
        UNMATCHED,
        ERROR        
    }

    public ConfigurationFile(Program parent_program) {
        this.parent_program = parent_program;
        build_command = null;
        clean_command = null;
    }
    
    string get_file_path() {
        return Path.build_filename(parent_program.get_top_directory(), ".valencia");
    }

    void load() {
        string file_path = get_file_path();

        if (!FileUtils.test(file_path, FileTest.EXISTS))
            return;

        string contents;
        try {
            FileUtils.get_contents(file_path, out contents);
        } catch (FileError e) {
            GLib.warning("Problem while trying to read %s\n", file_path);
            return;        
        }

        Regex config_regex;
        try {
            // Match something like: "word_group = value"
            config_regex = new Regex("""^\s*([^\s]+)\s*=\s*(.+)\s*$""");
        } catch (RegexError e) {
            GLib.warning("Problem creating a regex to parse the config file\n");
            return;
        }

        string[] lines = contents.split("\n");
        bool matched_version = false;
        bool matched_build = false;
        bool matched_clean = false;

        foreach (string line in lines) {
            // Ignore lines with whitespace
            line.chomp();
            if (line == "")
                continue;
        
            MatchInfo match_info;

            if (!config_regex.match(line, 0, out match_info)) {
                warning("Incorrect file format, ignoring...\n");
                return;
            }

            string match1 = match_info.fetch(1);
            string match2 = match_info.fetch(2);

            // Only match the version on the first line with text, any other line is a parse error
            if (!matched_build && !matched_clean && match1 == version_keyword && match2 == version) {
                matched_version = true;
                continue;
            } else if (!matched_version) {
                warning("Mismatched config file version, ignoring...\n");
                return;
            }
            
            if (match1 == build_command_keyword && match2 != null && build_command == null)
                build_command = match2;
            else if (match1 == clean_command_keyword && match2 != null && clean_command == null)
                clean_command = match2;
            else if (match1 == pkg_blacklist_keyword && match2 != null && pkg_blacklist == null)
                pkg_blacklist = match2;
            else {
                warning("Incorrect file format, ignoring...\n");
                return;
            }
        }
    }
    
    public string? get_build_command() {
        if (build_command == null)
            load();
            
        return build_command == null ? default_build_command : build_command;
    }

    public string? get_clean_command() {
        if (clean_command == null)
            load();
            
        return clean_command == null ? default_clean_command : clean_command;
    }
    
    public string get_pkg_blacklist() {
        if (pkg_blacklist == null)
            load();
        
        return pkg_blacklist ?? default_pkg_blacklist;
    }
    
    public string[] get_blacklisted_vapis() {
        if (blacklisted_vapis == null) {
            string blacklist = get_pkg_blacklist();
            if (blacklist == null || blacklist.length == 0) {
                blacklisted_vapis = new string[0];
            } else {
                blacklisted_vapis = blacklist.split(";");
                for (int ctr = 0; ctr < blacklisted_vapis.length; ctr++)
                    blacklisted_vapis[ctr] = blacklisted_vapis[ctr].strip() + ".vapi";
            }
        }
        
        return blacklisted_vapis;
    }
    
    public void update(string new_build_command, string new_clean_command, string new_pkg_blacklist) {
        build_command = new_build_command;
        clean_command = new_clean_command;
        pkg_blacklist = new_pkg_blacklist;
        
        string file_path = get_file_path();
        FileStream file = FileStream.open(file_path, "w");
        
        if (file == null) {
            warning("Could not open %s for writing\n", file_path);
            return;
        }
        
        file.printf("%s = %s\n", version_keyword, version);
        file.printf("%s = %s\n", build_command_keyword, build_command);
        file.printf("%s = %s\n", clean_command_keyword, clean_command);
        file.printf("%s = %s\n", pkg_blacklist_keyword, pkg_blacklist);
        
        // clear to force a re-load; note that Valencia currently doesn't re-load the cache after
        // the first pass, so this is kind of moot
        blacklisted_vapis = null;
    }

    public void update_location(string old_directory) {
        File old_file = File.new_for_path(Path.build_filename(old_directory, ".valencia"));
        File new_file = File.new_for_path(get_file_path());

        if (!FileUtils.test(old_file.get_path(), FileTest.EXISTS))
            return;

        try {
            old_file.copy(new_file, FileCopyFlags.OVERWRITE, null, null);
        } catch (Error e) {
            GLib.warning("Problem while copying old .valencia to %s\n", new_file.get_path());
        }

        try {
            old_file.delete(null);
        } catch (Error e) {
            GLib.warning("Problem while deleting %s\n", old_file.get_path());
        }
    }

}

public class Program : Object {
    public ErrorList error_list;

    string top_directory;
    
    int total_filesize;
    int parse_list_index;
    ArrayList<string> sourcefile_paths = new ArrayList<string>();
    bool parsing;
    
    ArrayList<SourceFile> sources = new ArrayList<SourceFile>();
    static ArrayList<SourceFile> system_sources = new ArrayList<SourceFile>();
    
    static ArrayList<Program> programs;
    
    Makefile makefile;
    public ConfigurationFile config_file;

    bool recursive_project;
    uint local_parse_source_id = 0;
    uint system_parse_source_id = 0;
    
    signal void local_parse_complete();
    public signal void system_parse_complete();
    public signal void parsed_file(double fractional_progress);

    Program(string directory) {
        error_list = null;
        top_directory = null;
        parsing = true;
        makefile = new Makefile();
        config_file = new ConfigurationFile(this);
        
        // Search for the program's build_root; if the top_directory still hasn't been modified
        // (meaning no makefile at all has been found), then just set it to the default directory
        File root_dir = File.new_for_path(directory);
        if (get_build_root_directory(root_dir)) {
            recursive_project = true;
        } else {
            // If no root directory was found, make sure there is a local top directory, and 
            // scan only that directory for sources
            top_directory = directory;
            recursive_project = false;
        }

        local_parse_source_id = Idle.add(parse_local_vala_files_idle_callback);
        
        programs.add(this);
    }
    
    ~Program() {
        if (local_parse_source_id != 0)
            Source.remove(local_parse_source_id);
        
        if (system_parse_source_id != 0)
            Source.remove(system_parse_source_id);
    }
    
    public static void wipe() {
        programs.clear();
        system_sources.clear();
    }
    
    // Returns true if a BUILD_ROOT or configure.ac was found: files should be found recursively
    // False if only the local directory will be used
    bool get_build_root_directory(GLib.File makefile_dir) {
        if (configure_exists_in_directory(makefile_dir))
            return true;
    
        GLib.File makefile_file = makefile_dir.get_child("Makefile");
        if (!makefile_file.query_exists(null)) {
            makefile_file = makefile_dir.get_child("makefile");
            
            if (!makefile_file.query_exists(null)) {
                makefile_file = makefile_dir.get_child("GNUmakefile");
                
                if (!makefile_file.query_exists(null)) {
                    return goto_parent_directory(makefile_dir);
                }
            }
        }

        // Set the top_directory to be the first BUILD_ROOT we come across
        if (makefile.parse(makefile_file)) {
            set_paths(makefile_file);
            return true;
        }
        
        return goto_parent_directory(makefile_dir);
    }
    
    bool goto_parent_directory(GLib.File base_directory) {
        GLib.File parent_dir = base_directory.get_parent();
        return parent_dir != null && get_build_root_directory(parent_dir);
    }
    
    bool configure_exists_in_directory(GLib.File configure_dir) {
        GLib.File configure = configure_dir.get_child("configure.ac");
        
        if (!configure.query_exists(null)) {
            configure = configure_dir.get_child("configure.in");
    
            if (!configure.query_exists(null))
                return false;
        }

        // If there's a configure file, don't bother parsing for a makefile        
        top_directory = configure_dir.get_path();
        makefile.reset_paths();

        return true;
    }

    void set_paths(GLib.File makefile_file) {
        makefile.path = makefile_file.get_path();
        top_directory = Path.get_dirname(makefile.path);
    }

    string get_versioned_vapi_directory() {
        // Sort of a hack to get the path to the system vapi file directory. Gedit may hang or 
        // crash if the vala compiler .so is not present...
        Vala.CodeContext context = new Vala.CodeContext();
        string path = context.get_vapi_path("gobject-2.0");
        return Path.get_dirname(path);
    }

    Gee.ArrayList<string> get_unversioned_vapi_directories() {
        Gee.ArrayList<string> valid_data_dirs = new Gee.ArrayList<string>();
        foreach (unowned string data_dir in Environment.get_system_data_dirs()) {
            string temp_path = Path.build_filename(data_dir, "vala", "vapi");
            if (FileUtils.test(temp_path, FileTest.EXISTS)) {
                valid_data_dirs.add(temp_path);
            }
        }
        return valid_data_dirs;
    }

    Gee.ArrayList<string> get_system_vapi_directories() {
        Gee.ArrayList<string> directories = get_unversioned_vapi_directories();
        directories.add(get_versioned_vapi_directory());
        return directories;
    }

    void finish_local_parse() {
        parsing = false;
        local_parse_complete();
        // Emit this now, otherwise it will never be emitted, since the system parsing is done
        if (system_sources.size > 0)
            system_parse_complete();
    }

    bool parse_local_vala_files_idle_callback() {
        local_parse_source_id = 0;
        
        if (sourcefile_paths.is_empty) {
            // Don't parse system files locally!
            foreach (string system_directory in get_system_vapi_directories()) {
                if (top_directory == system_directory || 
                    (recursive_project && dir_has_parent(system_directory, top_directory))) {
                    finish_local_parse();
                    return false;
                }
            }
            
            cache_source_paths_in_directory(top_directory, recursive_project);
        }

        // We can reasonably parse 3 files in one go to take a load off of X11
        for (int i = 0; i < 3; ++i) {
            if (!parse_vala_file(sources)) {
                finish_local_parse();
                return false;                
            }
        }
        
        return true;
    }

    bool parse_system_vala_files_idle_callback() {
        system_parse_source_id = 0;
        
        if (sourcefile_paths.size == 0) {
            foreach (string system_directory in get_system_vapi_directories()) {
                cache_source_paths_in_directory(system_directory, true);
            }
        }

        for (int i = 0; i < 3; ++i) {
            if (!parse_vala_file(system_sources)) {
                parsing = false;
                sort_system_files();
                system_parse_complete();
                return false;
            }
        }

        return true;
    }

    // Takes the next vala file in the sources path list and parses it. Returns true if there are
    // more files to parse, false if there are not.
    bool parse_vala_file(ArrayList<SourceFile> source_list) {
        if (sourcefile_paths.is_empty) {
            return false;
        }
    
        string path = sourcefile_paths.get(parse_list_index);

        // The index is incremented here because if an error happens, we want to skip this file
        // next time around
        ++parse_list_index;        
        
        SourceFile source = new SourceFile(this, path);
        string contents;
        
        try {
            FileUtils.get_contents(path, out contents);
        } catch (GLib.FileError e) {
            // needs a message box? stderr.printf message?
            return parse_list_index == sourcefile_paths.size;
        }

        Parser parser = new Parser();
        parser.parse(source, contents);
        source_list.add(source);
        // Only show parsing progress if the filesize is over 1MB (1048576 bytes == 1 megabyte)
        if (total_filesize > 1048576)
            parsed_file((double) (parse_list_index) / sourcefile_paths.size);
        
        return parse_list_index != sourcefile_paths.size;
    }

    // Find all Vala files in the given directory (and its subdirectories, if recursive is true)
    // and store them in sourcefile_paths.  Returns the total size of the files.
    int cache_source_paths_in_directory(string directory, bool recursive) {
        parse_list_index = 0;
        
        Dir dir;
        try {
            dir = Dir.open(directory);
        } catch (GLib.FileError e) {
            GLib.warning("Error opening directory: %s\n", directory);
            return 0;
        }
        
        total_filesize = 0;
        
        while (true) {
            string file = dir.read_name();

            if (file == null)
                break;

            string path = Path.build_filename(directory, file);

            if (is_vala(file)) {
                if (file in config_file.get_blacklisted_vapis()) {
                    debug("Skipping blacklisted package %s", file);
                    
                    continue;
                }
                
                sourcefile_paths.add(path);
                
                try {
                    GLib.File sourcefile = GLib.File.new_for_path(path);
                    GLib.FileInfo info = sourcefile.query_info("standard::size", 
                                                               GLib.FileQueryInfoFlags.NONE, null);
                    total_filesize += (int) info.get_size();
                } catch (GLib.Error e) { }
            }
            else if (recursive && GLib.FileUtils.test(path, GLib.FileTest.IS_DIR))
                total_filesize += cache_source_paths_in_directory(path, true);
        }
        
        return total_filesize;
    }
    
    void parse_system_vapi_files() {
        // Don't parse system vapi files twice
        if (system_sources.size > 0)
            return;

        // Only begin parsing vapi files after the local vapi files have been parsed        
        if (is_parsing()) {
            local_parse_complete.connect(parse_system_vapi_files);
        } else {
            parsing = true;
            parse_list_index = 0;
            sourcefile_paths.clear();
            
            if (system_parse_source_id != 0)
                Source.remove(system_parse_source_id);
            
            system_parse_source_id = Idle.add(this.parse_system_vala_files_idle_callback);
        }
    }
    
    void sort_system_files() {
        // puts glib.vapi first in the list to avoid built-in type vala profile conflicts 
        // (posix.vapi contains definitions for 'int', jumping to definition may open posix.vapi
        // instead of glib.vapi. Perhaps one day we will be smart enough to know which profile
        // to use)
        
        for (int i = 0; i < system_sources.size; ++i) {
            SourceFile glib_file = system_sources.get(i);
            assert(glib_file != null);

            if (!glib_file.filename.has_suffix("glib-2.0.vapi"))
                continue;
            
            if (i == 0)
                return;
            
            SourceFile swap_file = system_sources.get(0);
            assert(swap_file != null);
            
            system_sources.set(0, glib_file);
            system_sources.set(i, swap_file);
            break;
        }
    }
    
    public static bool is_vala(string filename) {
        return filename.has_suffix(".vala") ||
               filename.has_suffix(".vapi") ||
               filename.has_suffix(".cs");    // C#
    }

    public bool lookup_in_namespace1(ArrayList<SourceFile> source_list, string? namespace_name, 
                                        SymbolSet symbols, bool vapi) {
        foreach (SourceFile source in source_list)
            if (source.filename.has_suffix(".vapi") == vapi) {
                if (source.lookup_in_namespace(namespace_name, symbols))
                    return true;
            }
        return false;
    }

    public bool lookup_in_namespace(string? namespace_name, SymbolSet symbols) {
        // First look in non-vapi files; we'd like definitions here to have precedence.
        if (!lookup_in_namespace1(sources, namespace_name, symbols, false)) {
            if (symbols.local_symbols_only())
                return false;
            if (!lookup_in_namespace1(sources, namespace_name, symbols, true)); // .vapi files
                if (!lookup_in_namespace1(system_sources, namespace_name, symbols, true))
                    return false;
        }
        return true;
    }

    SourceFile? find_source1(string path, ArrayList<SourceFile> source_list) {
        foreach (SourceFile source in source_list) {
            if (source.filename == path)
                return source;
        }
        return null;
    }

    public SourceFile? find_source(string path) {
        SourceFile sf = find_source1(path, sources);
        if (sf == null)
            sf = find_source1(path, system_sources);

        return sf;
    }
    
    // Update the text of a (possibly new) source file in this program.
    void update1(string path, string contents) {
        SourceFile source = find_source(path);
        if (source == null) {
            source = new SourceFile(this, path);
            sources.add(source);
        } else source.clear();
        new Parser().parse(source, contents);
    }
    
    public void update(string path, string contents) {
        if (!is_vala(path))
            return;
            
        if (recursive_project && dir_has_parent(path, top_directory)) {
            update1(path, contents);
            return;
        }
        
        string path_dir = Path.get_dirname(path);    
        if (top_directory == path_dir)
            update1(path, contents);
    }
    
    static Program? find_program(string dir) {
        if (programs == null)
            programs = new ArrayList<Program>();
            
        foreach (Program p in programs)
            if (p.top_directory == dir ||
                p.recursive_project && dir_has_parent(dir, p.top_directory))
                return p;
                
        return null;
    }
    
    // Find or create the Program containing the source file with the given path.
    public static Program find_containing(string path, bool parse_system_vapi = false) {
        string dir = Path.get_dirname(path);
        Program p = find_program(dir);
        if (p == null)
            p = new Program(dir);
        
        if (parse_system_vapi)
            p.parse_system_vapi_files();
        
        return p;
    }
    
    public static Program? find_existing(string path) {
        string dir = Path.get_dirname(path);
        return find_program(dir);    
    }

    // Update the text of a (possibly new) source file in any existing program.
    // If (contents) is null, we read the file's contents from disk.
    public static void update_any(string path, string? contents) {
        if (!is_vala(path))
            return;
          
          // If no program exists for this file, don't even bother looking
        string dir = Path.get_dirname(path);
          if (find_program(dir) == null)
              return;
          
        string contents1;        // owning variable
        if (contents == null) {
            try {
                FileUtils.get_contents(path, out contents1);
            } catch (FileError e) { 
                GLib.warning("Unable to open %s for updating\n", path);
                return; 
            }
            contents = contents1;
        }

        // Make sure to update the file for each sourcefile
        foreach (Program program in programs) {
            SourceFile sf = program.find_source(path);
                if (sf != null)
                    program.update1(path, contents);
        }
    }

    public static void rescan_build_root(string sourcefile_path) {
        Program? program = find_program(Path.get_dirname(sourcefile_path));
        
        if (program == null)
            return;

        File current_dir = File.new_for_path(Path.get_dirname(sourcefile_path));        
        string old_top_directory = program.top_directory;
        string local_directory = current_dir.get_path();

        // get_makefile_directory will set top_directory to the path of the makefile it found - 
        // if the path is the same as the old top_directory, then no changes have been made
        bool found_root = program.get_build_root_directory(current_dir);

        // If a root was found and the new and old directories are the same, the old root was found:
        // nothing changes.
        if (found_root && old_top_directory == program.top_directory)
            return;
        if (!found_root && old_top_directory == local_directory)
            return;

        // If a new root was found, get_makefile_directory() will have changed program.top_directory
        // already; if not, then we need to set it to the local directory manually
        if (!found_root)
            program.top_directory = local_directory;
            
        // Make sure to move any .valencia files from the old root to the new root
        program.config_file.update_location(old_top_directory);

        // The build root has changed, so: 
        // 1) delete the old root
        assert(programs.size > 0);
        programs.remove(program);

         // 2) delete a program rooted at the new directory if one exists
        foreach (Program p in programs)
            if (p.top_directory == program.top_directory)
                programs.remove(p);
            
         // 3) create a new program at new build root
        new Program(program.top_directory);
    }    
    
    public string get_top_directory() {
        return top_directory;
    }

    public string? get_binary_run_path() {
        if (makefile.relative_binary_run_path == null)
            return null;
        return Path.build_filename(top_directory, makefile.relative_binary_run_path);
    }
    
    public bool get_binary_is_executable() {
        string? binary_path = get_binary_run_path();
        return binary_path != null && !binary_path.has_suffix(".so");
    }
    
    public void reparse_makefile() {
        makefile.reparse();
    }

    // Tries to find a full path for a filename that may be a sourcefile (or another file that
    // happens to reside in a sourcefile directory, like a generated .c file)
    public string? get_path_for_filename(string filename) {
        if (Path.is_absolute(filename))
            return filename;

        // Make sure the whole basename is matched, not just part of it
        string relative_path = (filename.contains(Path.DIR_SEPARATOR_S)) ? 
                                  filename : Path.DIR_SEPARATOR_S + filename;
        
        // Search for the best partial match possible
        foreach (SourceFile sf in sources) {
            if (sf.filename.has_suffix(relative_path))
                return sf.filename;
        }

        // If no direct match could be made, try searching all directories that the source files
        // are in for a file that matches the basename
        string basename = Path.get_basename(filename);
        Gee.ArrayList<string> dirs = new ArrayList<string>();
        foreach (SourceFile sf in sources) {
            string dir = Path.get_dirname(sf.filename);
            if (!dirs.contains(dir))
                dirs.add(dir);
        }
        foreach (string dir_str in dirs) {
            Dir directory;
            try {
                directory = Dir.open(dir_str);
            } catch (GLib.FileError e) {
                GLib.warning("Could not open %s for reading.\n", dir_str);
                return null;
            }
            string file = directory.read_name();
            while(file != null) {
                if (basename == file)
                    return Path.build_filename(dir_str, file);
                file = directory.read_name();
            }
        }
        
        return null;
    }

    public bool is_parsing() {
        return parsing;
    }
    
}

} // namespace Valencia

