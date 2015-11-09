/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Vala;

namespace Valencia {

public class ScanScope : Object {
  public int depth;
  public int start_pos;
  public int end_pos;
  
  public ScanScope(int depth, int start_pos, int end_pos) {
      this.depth = depth;
      this.start_pos = start_pos;
      this.end_pos = end_pos;
  }
}

public class ParseInfo : Object {
    public Expression inner;
    public Expression outer;
    public int outer_pos;
    
    public ParseInfo(Expression? inner) {
        this.inner = inner;
    }
}

public class Parser : Object {
    SourceFile source;
    Scanner scanner;
    Namespace current_namespace;
    
    Token peek_token() { return scanner.peek_token(); }
    Token next_token() { return scanner.next_token(); }
    
    bool accept(Token t) { return scanner.accept_token(t); }
    
    // Skip to a right brace or semicolon.
    void skip() {
        int depth = 0;
        while (true)
            switch (next_token()) {
                case Token.EOF:
                    return;
                case Token.LEFT_BRACE:
                    ++depth;
                    break;
                case Token.RIGHT_BRACE:
                    if (--depth <= 0) {
                        accept(Token.SEMICOLON);
                        return;
                    }
                    break;
                case Token.SEMICOLON:
                    if (depth == 0)
                        return;
                    break;
            }
    }

    Expression? parse_type() {
        accept(Token.UNOWNED) || accept(Token.WEAK);
        if (!accept(Token.ID))
            return null;
        Expression t = new Id(scanner.val());
        while (accept(Token.PERIOD)) {
            if (!accept(Token.ID))
                return null;
            t = new CompoundExpression(t, scanner.val());
        }
        if (accept(Token.LESS_THAN)) {    // parameterized type
            if (parse_type() == null)
                return null;
            while (!accept(Token.GREATER_THAN)) {
                if (!accept(Token.COMMA) || parse_type() == null)
                    return null;
            }
        }
        while (true) {
            if (accept(Token.QUESTION_MARK) || accept(Token.ASTERISK) || accept(Token.HASH))
                continue;
            if (accept(Token.LEFT_BRACKET)) {
                accept(Token.RIGHT_BRACKET);
                continue;
            }
            break;
        }
        return t;
    }
    
    // Skip an expression, looking for a following comma, right parenthesis,
    // semicolon or right brace.
    void skip_expression() {
        int depth = 0;
        while (!scanner.eof()) {
            switch (peek_token()) {
                case Token.COMMA:
                case Token.RIGHT_BRACE:
                case Token.SEMICOLON:
                    if (depth == 0)
                        return;
                    break;
                case Token.LEFT_PAREN:
                    ++depth;
                    break;
                case Token.RIGHT_PAREN:
                    if (depth == 0)
                        return;
                    --depth;
                    break;
            }
            next_token();
        }
    }

    Parameter? parse_parameter() {
        if (accept(Token.ELLIPSIS))
            return null;    // end of parameter list
        skip_attributes();
        accept(Token.OUT) || accept(Token.REF) || accept(Token.OWNED);
        Expression type = parse_type();
        if (type == null || !accept(Token.ID))
            return null;
        Parameter p = new Parameter(type, scanner.val(), source, scanner.start, scanner.end);
        if (accept(Token.EQUALS))
            skip_expression();
        return p;
    }
    
    // Parse an expression, returning the expression's type if known.
    Expression? parse_expression() {
        if (accept(Token.NEW)) {
            Expression type = parse_type();
            if (accept(Token.LEFT_PAREN)) {
                while (true) {
                    skip_expression();
                    if (!accept(Token.COMMA))
                        break;
                }
                if (accept(Token.RIGHT_PAREN)) {
                    Token token = peek_token();
                    if (token == Token.SEMICOLON || token == Token.COMMA)
                        return type;
                }
            }
        }

        // Parse struct/array initializers
        if (peek_token() == Token.LEFT_BRACE) {
            int depth = 0;
            // Look for semicolons to handle incorrect syntax better than skipping to the next scope
            while (!scanner.eof() && peek_token() != Token.SEMICOLON) {
                if (accept(Token.LEFT_BRACE))
                    ++depth;
                else if (accept(Token.RIGHT_BRACE) && --depth == 0)
                    break;
                else next_token();
            }
        } else skip_expression();
        return null;
    }
    
    LocalVariable? parse_local_variable(Expression type) {
        if (!accept(Token.ID))
            return null;

        string name = scanner.val();
        LocalVariable v = new LocalVariable(type, name, source, scanner.start, scanner.end);
        if (accept(Token.EQUALS)) {
            Expression inferred_type = parse_expression();
            if (v.type.to_string() == "var" && inferred_type != null)
                v.type = inferred_type;
        }
        
        return v;
    }

    For? parse_foreach() {
        int start = scanner.start;
        if (!accept(Token.LEFT_PAREN))
            return null;
        Expression type = parse_type();
        if (type == null) {
            skip();
            return null;
        }

        int declaration_start = scanner.start;
        ArrayList<LocalVariable> variables = new ArrayList<LocalVariable>();
        LocalVariable v = parse_local_variable(type);
        if (v == null)
            return null;
        
        while (v != null) {
            variables.add(v);
            if (!accept(Token.COMMA))
                break;
            v = parse_local_variable(type);
        }

        DeclarationStatement declaration = new DeclarationStatement(variables, declaration_start,
                                                                    scanner.end);

        // Both for and foreach need to skip to the right parenthesis after declaring variables
        do {
            skip_expression();
        } while (!scanner.eof() && accept(Token.SEMICOLON));
        
        if (!accept(Token.RIGHT_PAREN)) {
            skip();
            return null;
        }
        Statement s = parse_statement();
        return new For(declaration, s, start, scanner.end);
    }

    Statement? parse_statement() {
        if (accept(Token.FOREACH) || accept(Token.FOR))
            return parse_foreach();

        Expression type = parse_type();
        if (type != null && peek_token() == Token.ID) {
            int start = scanner.start;
            ArrayList<LocalVariable> variables = new ArrayList<LocalVariable>();

            LocalVariable? v = parse_local_variable(type);
            while (v != null) {
                variables.add(v);
                if (!accept(Token.COMMA))
                    break;
                v = parse_local_variable(type);
            }

            if (accept(Token.SEMICOLON))
                return new DeclarationStatement(variables, start, scanner.end);
        }

        // We found no declaration.  Scan through the remainder of the
        // statement, looking for an embedded block.
        while (true) {
            Token t = peek_token();
            if (t == Token.EOF || t == Token.RIGHT_BRACE)
                // If we see a right brace, then this statement is unterminated:
                // it has no semicolon.  This might happen if the user is still typing
                // the statement.  We don't want to consume the brace character.
                return null;
            switch (next_token()) {
                case Token.SEMICOLON:
                    return null;
                case Token.LEFT_BRACE:
                    return parse_block();
            }
        }
    }

    // Parse a block after the opening brace.    
    Block? parse_block() {
        Block b = new Block();
        b.start = scanner.start;
        while (!scanner.eof() && !accept(Token.RIGHT_BRACE)) {
            Statement s = parse_statement();
            if (s != null)
                b.statements.add(s);
        }
        b.end = scanner.end;
        return b;
    }

    // Parse a method.  Return the method object, or null on error.
    Method? parse_method(Method m, string input) {
        m.start = scanner.start;
        if (!accept(Token.LEFT_PAREN)) {
            skip();
            return null;
        }
        while (true) {
            Parameter p = parse_parameter();
            if (p == null)
                break;
            m.parameters.add(p);
            if (!accept(Token.COMMA))
                break;
        }
        if (!accept(Token.RIGHT_PAREN)) {
            skip();
            return null;
        }

        // Look for a semicolon or left brace.  (There may be a throws clause in between.)
        Token t = Token.NONE;
        do {
            t = next_token();
            if (t == Token.EOF)
                return null;
        } while (t != Token.LEFT_BRACE && t != Token.SEMICOLON);

        // Take the string from the return type all the way to the last ')'
        m.update_prototype(input.ndup((char *) scanner.get_start() - (char *) input));
        
        if (t == Token.LEFT_BRACE)
            m.body = parse_block();

        m.end = scanner.end;
        return m;
    }

    Symbol? parse_method_or_field(Class? enclosing_class) {
        bool parse_signal = false, parse_delegate = false;
        weak string input = scanner.get_start_after_comments();
        if (accept(Token.SIGNAL))
            parse_signal = true;
        else if (accept(Token.DELEGATE))
            parse_delegate = true;
        
        Expression type = parse_type();
        if (type == null) {
            skip();
            return null;
        }
        
        if (enclosing_class != null) {
            if (peek_token() == Token.LEFT_PAREN && type.to_string() == enclosing_class.name)
                return parse_method(new Constructor(null, enclosing_class, source), input);
            // Parse named constructors
            else if (type is CompoundExpression) {
                CompoundExpression qualified_type = type as CompoundExpression;
                if (qualified_type.left.to_string() == enclosing_class.name)
                    return parse_method(new Constructor(qualified_type.right, enclosing_class, source), input);
            }
        }
        
        if (!accept(Token.ID)) {
            skip();
            return null;
        }
        switch (peek_token()) {
            case Token.SEMICOLON:
            case Token.EQUALS:
                Field f = new Field(type, scanner.val(), source, scanner.start, 0);
                skip();
                f.end = scanner.end;
                return f;
            case Token.LEFT_PAREN:
                Method m;
                if (parse_signal)
                    m = new VSignal(scanner.val(), type, source);
                else if (parse_delegate)
                    m = new Delegate(scanner.val(), type, source);
                else m = new Method(scanner.val(), type, source);
                return parse_method(m, input);
            case Token.LEFT_BRACE:
                Property p = new Property(type, scanner.val(), source, scanner.start, 0);
                next_token();
                p.body = parse_block();
                p.end = scanner.end;
                return p;
            default:
                skip();
                return null;
        }
    }

    bool is_modifier(Token t) {
        switch (t) {
            case Token.ABSTRACT:
            case Token.ASYNC:
            case Token.CONST:
            case Token.EXTERN:
            case Token.INLINE:
            case Token.INTERNAL:
            case Token.NEW:
            case Token.OVERRIDE:
            case Token.PRIVATE:
            case Token.PROTECTED:
            case Token.PUBLIC:
            case Token.STATIC:
            case Token.VIRTUAL:
                return true;
            default:
                return false;
        }
    }

    void skip_attributes() {
        while (accept(Token.LEFT_BRACKET))
            while (!scanner.eof() && next_token() != Token.RIGHT_BRACKET)
                ;
    }

    void skip_modifiers() {
        while (is_modifier(peek_token()))
            next_token();
    }

    Construct? parse_construct() {
        if (!accept(Token.CONSTRUCT))
            return null;
        int start = scanner.start;
        if (!accept(Token.LEFT_BRACE))
            return null;
        Block b = parse_block();
        return b == null ? null : new Construct(b, start, scanner.end);
    }

    Node? parse_member(Class? enclosing_class) {
        skip_attributes();
        skip_modifiers();
        Token t = peek_token();
        switch (t) {
            case Token.NAMESPACE:
                if (enclosing_class == null) {
                    next_token();    // move past 'namespace'
                    return parse_namespace();
                }
                skip();
                return null;
            case Token.CLASS:
            case Token.INTERFACE:
            case Token.STRUCT:
            case Token.ENUM:
                next_token();
                return parse_class(t, enclosing_class);
            case Token.CONSTRUCT:
                return parse_construct();
            default:
                return parse_method_or_field(enclosing_class);
        }
    }

    Namespace? parse_containing_namespace(string name, Token container_type, 
                                          Class? enclosing_class) {
        Namespace n = open_namespace(name);

        Namespace parent = current_namespace;
        current_namespace = n;

        TypeSymbol inner = parse_class(container_type, enclosing_class);
        if (inner == null)
            n = null;
        else {
            n.symbols.add(inner);
            close_namespace(n);
        }
        
        current_namespace = parent;
        return n;
    }

    TypeSymbol? parse_class(Token container_type, Class? enclosing_class) {
        if (!accept(Token.ID)) {
            skip();
            return null;
        }
        string name = scanner.val();

        if (accept(Token.PERIOD))
            return parse_containing_namespace(name, container_type, enclosing_class);

        Class cl;
        if (container_type == Token.INTERFACE)
            cl = new Interface(name, source, enclosing_class);
        else cl = new Class(name, source, enclosing_class);
        cl.start = scanner.start;
        
        // Make sure to discard any generic qualifiers
        if (accept(Token.LESS_THAN)) {
            while (accept(Token.ID) || accept(Token.COMMA))
                ;
            accept(Token.GREATER_THAN);
        }

        if (accept(Token.COLON))
            while (true) {
                Expression type = parse_type();
                if (type == null) {
                    skip();
                    return null;
                }
                cl.super.add(type);
                if (!accept(Token.COMMA))
                    break;
            }
        if (!accept(Token.LEFT_BRACE))
            return null;

        if (container_type == Token.ENUM) {
            while (true) {
                skip_attributes();
                if (!accept(Token.ID))
                    break;
                Field f = new Field(new Id(name), scanner.val(), source, scanner.start, 0);
                if (accept(Token.EQUALS))
                    skip_expression();
                f.end = scanner.end;
                cl.members.add(f);
                if (!accept(Token.COMMA))
                    break;
            }
            accept(Token.SEMICOLON);
        }
        
        while (!scanner.eof() && !accept(Token.RIGHT_BRACE)) {
            Node n = parse_member(cl);
            if (n != null)
                cl.members.add(n);
        }

        // make sure the class has a constructor, if not, add a default one
        if (container_type == Token.CLASS) {
            bool found_constructor = false;
            foreach (Node n in cl.members) {
                Constructor c = n as Constructor;
                if (c == null)
                    continue;
                    
                if (c.name == null) {
                    found_constructor = true;
                    break;
                }
            }

            if (!found_constructor) {
                Constructor c = new Constructor(null, cl, source);
                c.start = cl.start;
                c.end = c.start;
                c.update_prototype(cl.name + "()");
                cl.members.add(c);
            }
        }
        
        cl.end = scanner.end;
        return cl;
    }

    static string join(string? a, string b) {
        return a == null ? b : a + "." + b;
    }

    Namespace open_namespace(string name) {
        Namespace n = new Namespace(name, join(current_namespace.full_name, name), source);
        n.start = scanner.start;
        return n;
    }
    
    void close_namespace(Namespace n) {
        source.namespaces.add(n);
        n.end = scanner.end;
    }

    Namespace? parse_namespace() {
        if (!accept(Token.ID)) {
            skip();
            return null;
        }
        
        string name = scanner.val();
        Namespace n = open_namespace(name);
        
        Namespace parent = current_namespace;
        current_namespace = n;
        
        if (accept(Token.PERIOD)) {
            Namespace inner = parse_namespace();
            if (inner == null)
                n = null;
            else n.symbols.add(inner);
        } else if (accept(Token.LEFT_BRACE)) {
            while (!scanner.eof() && !accept(Token.RIGHT_BRACE)) {
                Symbol s = parse_member(null) as Symbol;
                if (s != null)
                    n.symbols.add(s);
            }
        } else {
            skip();
            n = null;
        }

        if (n != null)
            close_namespace(n);    
        
        current_namespace = parent;
        return n;
    }

    string? parse_using() {
        if (!accept(Token.ID)) {
            skip();
            return null;
        }
        string s = scanner.val();
        skip();
        return s;
    }

    public void parse(SourceFile source, string input) {
         this.source = source;
         scanner = new Scanner(input);
         while (accept(Token.USING)) {
             string s = parse_using();
             if (s != null)
                 source.add_using_namespace(s);
         }
         current_namespace = source.top;
         while (!scanner.eof()) {
             Symbol s = parse_member(null) as Symbol;
             if (s != null)
                 source.top.symbols.add(s);
         }
         source.top.end = scanner.end;
    }

    // namespaces, interfaces/classes/structs/enums, and methods count as enclosing scopes
    public ScanScope? find_enclosing_scope(string input, int pos, bool classes_only) {
        scanner = new Scanner(input);

        Stack<ScanScope> scopes = new Stack<ScanScope>();
        int depth = 0;
        bool token_is_class = false;
        bool token_is_namespace = false;
        
        while (scanner.end < pos) {
            Token t = next_token();
            if (t == Token.EOF)
                break;
            if (t == Token.CLASS)
                token_is_class = true;
            else if (t == Token.NAMESPACE)
                token_is_namespace = true;
            else if (t == Token.LEFT_BRACE)
                ++depth;
            else if (t == Token.RIGHT_BRACE) {
                --depth;
                if (scopes.size() > 0 && scopes.top().depth == depth && scanner.end < pos)
                    scopes.pop();
            // Don't bother looking at the token if it's classes only and the token isn't a class
            } else if (t == Token.ID && ((!classes_only && !token_is_class) || token_is_class)) {
                int position = scanner.start;
                while (true) {
                    if (scanner.end >= pos)
                        return (scopes.size() > 0) ? scopes.top() : null;
                    if (!accept(Token.PERIOD) || !accept(Token.ID))
                        break;
                }
                int end = scanner.end;

                if (!classes_only && peek_token() == Token.LEFT_PAREN) {
                    // skip to the end of the method declaration to check for a left brace
                    int unmatched_parens = 0;
                    while (scanner.end < pos) {
                        t = next_token();
                        if (t == Token.SEMICOLON)
                            break;
                        else if (t == Token.LEFT_PAREN)
                            ++unmatched_parens;
                        else if (t == Token.RIGHT_PAREN)
                            if (--unmatched_parens == 0)
                                break;
                    }

                    // Borrow the token_is_class variable temporarily - there's no need to use 
                    // another variable when this will be reset to false
                    if (peek_token() == Token.LEFT_BRACE)
                        token_is_class = true;
                }

                if (token_is_class || token_is_namespace)
                    scopes.push(new ScanScope(depth, position, end));
                token_is_class = false;
                token_is_namespace = false;
            } else {
                token_is_class = false;
                token_is_namespace = false;
            }
        }
        
        return (scopes.size() > 0) ? scopes.top() : null;
    }

}

}

void main(string[] args) {
    if (args.length < 2) {
        stderr.puts("usage: symbol <file>\n");
        return;
    }
    string filename = args[1];
    string source;
    try {
        if (!FileUtils.get_contents(filename, out source)) {
            stderr.puts("can't read file\n");
            return;
        }
    } catch (FileError e) {
        stderr.printf("error reading file: %s\n", e.message);
        return;
    }

    Valencia.SourceFile sf = new Valencia.SourceFile(null, filename);
    new Valencia.Parser().parse(sf, source);
    sf.print(0);
}

