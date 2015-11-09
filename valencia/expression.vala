/* Copyright 2009-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Valencia {

public abstract class Expression : Object {
    public abstract string to_string();
}

public class Id : Expression {
    public string name;
    
    public Id(string name) { 
        this.name = name;
    }
    
    public override string to_string() {
        return name;
    }
}

public class This : Expression {
    public override string to_string() { return "this"; }    
}

public class Base : Expression {
    public override string to_string() { return "base"; }
}

public class New : Expression {
    public Expression class_name;
    
    public New(Expression class_name) {
        this.class_name = class_name;
    }
    
    public override string to_string() {
        return "new " + class_name.to_string();
    }
}

public class MethodCall : Expression {
    public Expression method;
    
    public MethodCall(Expression method) {
        this.method = method;
    }
    
    public override string to_string() {
        return method.to_string() + "()";
    }
}

public class CompoundExpression : Expression {
    public Expression left;
    public string right;
    
    public CompoundExpression(Expression left, string right) {
        this.left = left;
        this.right = right;
    }
    
    public override string to_string() {
        return left.to_string() + "." + right;
    }
}

class ExpressionParser : Object {
    Scanner scanner;
    int pos;
    bool partial;
    
    public ExpressionParser(string input, int pos, bool partial) {
        scanner = new Scanner(input);
        this.pos = pos;
        this.partial = partial;
    }
    
    bool accept(Token t) { return scanner.accept_token(t); }
    
    ParseInfo parse_expr(bool nested) {
        int parens = 0;
        
        while (true) {
            Token t = scanner.next_token();
            if (t == Token.EOF || scanner.start > pos)
                break;
                
            bool is_new;
            if (t == Token.NEW) {
                is_new = true;
                t = scanner.next_token();
                if (scanner.start > pos)
                    break;
            } else is_new = false;
            
            if (t == Token.ID || (t == Token.THIS || t == Token.BASE) && !is_new) {
                Expression e = null;
                if (t == Token.ID)
                    e = new Id(scanner.val());
                else if (t == Token.THIS)
                    e = new This();
                else if (t == Token.BASE)
                    e = new Base();
                    
                while (true) {
                    if (scanner.end >= pos)
                        return new ParseInfo(is_new ? new New(e) : e);
                    if (accept(Token.LEFT_PAREN)) {
                        if (is_new) {
                            e = new New(e);
                            is_new = false;
                        }
                        int paren_pos = scanner.start;
                        ParseInfo info = parse_expr(true);
                        if (scanner.end > pos || info.inner != null || info.outer != null) {
                            if (info.outer == null) {
                                info.outer = e;
                                info.outer_pos = paren_pos;
                            }
                            return info;
                        }
                        e = new MethodCall(e);
                    }
                    if (!accept(Token.PERIOD))
                        break;
                    if (partial && scanner.end == pos)
                        e = new CompoundExpression(e, "");
                    else if (accept(Token.ID) && scanner.start <= pos)
                        e = new CompoundExpression(e, scanner.val());
                    else break;
                }
            }
            
            if (nested) {
                if (t == Token.LEFT_PAREN) {
                    ++parens;
                    continue;
                }
                if (t == Token.RIGHT_PAREN && --parens < 0)
                    break;
            }
        }
        
        return new ParseInfo(null);
    }

    public ParseInfo parse() { return parse_expr(false); }
}

}
