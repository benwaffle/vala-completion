/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Valencia {

enum Token {
    NONE,
    EOF,
    CHAR,    // an unrecognized punctuation character
    CHAR_LITERAL,    // a literal such as 'x'
    STRING_LITERAL,
    ID,
    
    // punctuation
    ASTERISK, LEFT_BRACE, RIGHT_BRACE, LEFT_BRACKET, RIGHT_BRACKET, COLON, COMMA, EQUALS, ELLIPSIS,
    HASH, LEFT_PAREN, RIGHT_PAREN, PERIOD, QUESTION_MARK, SEMICOLON, LESS_THAN, GREATER_THAN,

    // keywords
    ABSTRACT, ASYNC, BASE, CLASS, CONST, CONSTRUCT, DELEGATE, ELSE, ENUM, EXTERN, FOR, FOREACH, IF,
    INLINE, INTERFACE, INTERNAL, NAMESPACE, NEW, OUT, OVERRIDE, OWNED, PRIVATE, PROTECTED, PUBLIC,
    REF, RETURN, SIGNAL, STATIC, STRUCT, THIS, UNOWNED, USING, VIRTUAL, WEAK, WHILE
}

struct Keyword {
    public string name;
    public Token token;
}

const Keyword[] keywords = {
    { "abstract", Token.ABSTRACT },
    { "async", Token.ASYNC },
    { "base", Token.BASE },
    { "class", Token.CLASS },
    { "const", Token.CONST },
    { "construct", Token.CONSTRUCT },
    { "delegate", Token.DELEGATE },
    { "else", Token.ELSE }, 
    { "enum", Token.ENUM },
    { "extern", Token.EXTERN },
    { "for", Token.FOR },
    { "foreach", Token.FOREACH },
    { "if", Token.IF },
    { "inline", Token.INLINE },
    { "interface", Token.INTERFACE },
    { "internal", Token.INTERNAL },
    { "namespace", Token.NAMESPACE },
    { "new", Token.NEW },
    { "out", Token.OUT },
    { "override", Token.OVERRIDE },
    { "owned", Token.OWNED },
    { "private", Token.PRIVATE },
    { "protected", Token.PROTECTED },
    { "public", Token.PUBLIC },
    { "ref", Token.REF },
    { "return", Token.RETURN },
    { "signal", Token.SIGNAL },
    { "static", Token.STATIC },
    { "struct", Token.STRUCT },
    { "this", Token.THIS },
    { "unowned", Token.UNOWNED },
    { "using", Token.USING },
    { "virtual", Token.VIRTUAL },
    { "weak", Token.WEAK },
    { "while", Token.WHILE }
};

class Scanner : Object {
    // The lookahead token.  If not NONE, it extends from characters (token_start_char) to (input),
    // and from positions (token_start) to (input_pos).
    Token token = Token.NONE;
    
    weak string token_start_char;
    weak string input_begin;
    weak string input;
    
    int token_start;
    int input_pos;
    
    // The last token retrieved with next_token() extends from characters (start_char) to
    // (end_char), and from positions (start) to (end).
    weak string start_char;
    weak string end_char;
    public int start;    // starting character position
    public int end;        // ending character position
    
    public Scanner(string input) {
        this.input = input;
        input_begin = input;
    }

    void advance() {
        input = input.next_char();
        ++input_pos;
    }
    
    unichar peek_char() { return input.get_char(); }
    
    // Peek two characters ahead.
    unichar peek_char2() {
        return input == "" ? '\0' : input.next_char().get_char();
    }

    unichar next_char() {
        unichar c = peek_char();
        advance();
        return c;
    }
    
    bool accept(unichar c) {
        if (peek_char() == c) {
            advance();
            return true;
        }
        return false;
    }

    // Return true if the current token equals s.    
    bool match(string s) {
        char *p = token_start_char;
        char *q = s;
        while (*p != 0 && *q != 0 && *p == *q) {
            p = p + 1;
            q = q + 1;
        }
        return p == input && *q == 0;
    }

    // Read characters until we reach a triple quote (""") string terminator.
    void read_triple_string() {
        while (input != "")
            if (next_char() == '"' && accept('"') && accept('"'))
                return;
    }
    
    void skip_line() {
      while (input != "") {
          unichar c = next_char();
          if (c == '\n')
              break;
      }
    }
    
    bool is_first_token_on_line() {
        weak string line = input;
        // Go back to the '#' character
        line = line.prev_char();
        if (direct_equal(line, input_begin))
            return true;

        while (true) {
            line = line.prev_char();
            unichar c = line.get_char();
            if (direct_equal(line, input_begin) && c.isspace())
                return true;
            else if (c == '\n')
                return true;
            else if (!c.isspace())
                return false;
        }
    }

    Token read_token() {
        while (input != "") {
            token_start_char = input;
            token_start = input_pos;
            unichar c = next_char();

            if (c.isspace())
                continue;
            
            bool accept_all_chars_as_id = false;
            if (c == '@') {
                accept_all_chars_as_id = true;
                // Don't include the '@' in ID's
                token_start_char = input;
                token_start = input_pos;
                c = next_char();
            }

            // identifier start
            if (c.isalpha() || c == '_' || (accept_all_chars_as_id && c.isalnum())) { 
                while (true) {
                    c = peek_char();
                    if (!c.isalnum() && c != '_')
                        break;
                    advance();
                }
                // We don't use the foreach statement to iterate over the keywords array;
                // that would copy the Keyword structure (and the string it contains) on
                // each iteration, which would be slow.
                if (!accept_all_chars_as_id) {
                    for (int i = 0 ; i < keywords.length ; ++i)
                        if (match(keywords[i].name))
                            return keywords[i].token;
                }
                return Token.ID;
            }
            switch (c) {
                case '/':
                    unichar d = peek_char();
                    if (d == '/') {    // single-line comment
                        while (input != "" && next_char() != '\n')
                            ;
                        token_start_char = input;
                        token_start = input_pos;
                        continue;
                    }
                    if (d == '*') {       // multi-line comment
                        advance();    // move past '*'
                        while (input != "") { 
                            if (next_char() == '*' && peek_char() == '/') {
                                advance();    // move past '/'
                                break;
                            }
                        }
                        token_start_char = input;
                        token_start = input_pos;
                        continue;
                    }
                    return Token.CHAR;
                case '"':
                    if (accept('"')) {        // ""
                        if (accept('"'))    // """
                            read_triple_string();
                    } else {
                        while (input != "") {
                            unichar d = next_char();
                            if (d == '"' || d == '\n')
                                break;
                            else if (d == '\'')    // escape sequence
                                advance();
                        }
                    }
                    return Token.STRING_LITERAL;
                case '\'':
                    accept('\\');    // optional backslash beginning escape sequence
                    advance();
                    accept('\'');    // closing single quote
                    return Token.CHAR_LITERAL;
                case '*': return Token.ASTERISK;
                case '{': return Token.LEFT_BRACE;
                case '}': return Token.RIGHT_BRACE;
                case '[': return Token.LEFT_BRACKET;
                case ']': return Token.RIGHT_BRACKET;
                case ':': return Token.COLON;
                case ',': return Token.COMMA;
                case '=': return Token.EQUALS;
                case '#': 
                    if (is_first_token_on_line()) {
                        skip_line();
                        continue;
                    } else return Token.HASH;
                case '(': return Token.LEFT_PAREN;
                case ')': return Token.RIGHT_PAREN;
                case '.':
                    if (peek_char() == '.' && peek_char2() == '.') {
                        advance();
                        advance();
                        return Token.ELLIPSIS;
                    }
                    return Token.PERIOD;
                case '?': return Token.QUESTION_MARK;
                case ';': return Token.SEMICOLON;
                case '<': return Token.LESS_THAN;
                case '>': return Token.GREATER_THAN;
                default:  return Token.CHAR;
            }
        }
        return Token.EOF;
    }
    
    public Token peek_token() {
        if (token == Token.NONE)
            token = read_token();
        return token;
    }
    
    public Token next_token() { 
        Token t = peek_token();
        token = Token.NONE;
        start_char = token_start_char;
        end_char = input;
        start = token_start;
        end = input_pos;
        return t;
    }
    
    public bool accept_token(Token t) {
        if (peek_token() == t) {
            next_token();
            return true;
        }
        return false;
    }

    public bool eof() { return peek_token() == Token.EOF; }

    // Return the source text of the last token retrieved.
    public string val() {
        size_t bytes = (char *) end_char - (char *) start_char;
        return start_char.ndup(bytes);
    }

    public unowned string get_start() {
        return start_char;
    }

    public unowned string get_start_after_comments() {
        // Skip any comments after the end character and take the first character after them
        peek_token();
        return token_start_char;
    }
    
}

}
