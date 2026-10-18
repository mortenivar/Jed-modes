% Python mode
% File: pymode.sl v1.5.0
%
% For editing source code written in the Python programming language.
% Provides basic compatibility with Python mode under real Emacs
%
% Authors: Harri Pasanen <hpa@iki.fi>
%          Brien Barton <brien_barton@hotmail.com>
%
% following keys have python specific bindings:
%
% DELETE deletes to previous indent level
% TAB indents line
% ^C>  shifts line or region right
% ^C<  shifts line or region left
% ^Cf  formats buffer with ruff
% ^Ck  runs ruff linter on buffer and colors lines with errors/warnings
% ^C^C executes the region, or the buffer if region not marked.
% ^C\t reindents the region
% :    colon dedents appropriately
%
% See python_mode function for available hooks
%
% Shortcomings: does not really support triple-quoted strings in any way.
%

% Changes from v1.0:
%
% Major improvements, mostly done by Brien Barton:
%
% - execution of python code from JED
% - DFA syntax support
% - improved indent - dedent.
%

% Changes from v1.1:
%
% Minor fixes, by Tom Culliton
%
% - corrected a syntax error
% - fixed non-DFA syntax hilighting tables to work better
% - added the new assert keyword

% Changes from v1.2
% - autoindent correction

% Changes from v1.3
% - discard return value from run_shell_cmd
% - avoid use of create_array and explicit loop for initializing it.

% Changes from v1.3.1
%
% Additions/modifications by Morten Bo Johansen:
% 
% - Check buffer with "ruff check" and color error lines. Jump to them with keys
% - View description of ruff error code in current line in a pager.
% - Format buffer with "ruff format"
% - Fix some errors/warnings with ruff
% - Indentation after opening delimiters and indentation of closing delimiters
% 
% - Commented lines will wrap as you type and commented lines/paragraphs
%   may be formatted/wrapped with the key(s) tied to the format_paragraph()
%   function.
%
% - Typing <enter> after or within a commented line will continue the
%   comment on the next line.
%
% - Added a menu
% - Added a submenu with quick access to functions
% 
% - Changed and simplified the interface for executing code to use
%   run_program() instead of run_shell_cmd(). You may also enter options to
%   the program. It is primarily intended for executing code in the buffer
%   with the python3 program, but may also be used to execute other programs
%   on the buffer.
%   
% - Added a help function for word at point or a typed-in word.
% 
% - FIX: Many of the builtin kws were not properly highlighted.
% - Added many new keywords for highlighting
% 
% - FIX: The key combinations to move lines or regions left or right
%   were not using the right functions.
%    
% - Cleanup: Removed all the redundant comment/uncomment stuff as it is
%   handled with comment_region_or_line() from comments.sl which is
%   sourced by the now required wrap.sl
%
% - Removed the file_path() function as it is no longer used.
require("wrap");
require("keydefs");
require("process");
autoload("add_keywords", "syntax");

private variable Python = "python3";
  
$1 = "python";

ifnot (keymap_p ($1)) make_keymap ($1);

definekey_reserved("py_goto_next_or_prev_error_entry\(-1\)", Key_Up, $1);
definekey_reserved("py_goto_next_or_prev_error_entry\(1\)", Key_Down, $1);
definekey("py_help", Key_F1, $1);
definekey_reserved ("py_shift_right", ">", $1);
definekey_reserved ("py_shift_left", "<", $1);
definekey_reserved ("py_exec_cmd_on_buffer_or_region", "^C", $1); % Execute buffer, or region if defined
definekey_reserved ("py_format", "f", $1);    % Format buffer with "ruff format"
definekey_reserved ("py_check", "k", $1);    % Check buffer with "ruff check"
definekey_reserved ("py_reindent_region", "\t", $1);
definekey ("py_backspace_key", "^?", $1);
definekey ("indent_line", "\t", $1);
definekey ("py_electric_colon", ":", $1);
#ifdef MSWINDOWS
definekey ("py_help_on_word", "^@;", $1);
#endif

% Set the following to your favourite indentation level
custom_variable("Py_Indent_Level", 4);

% Set the following to your favourite pager
private variable Py_Pager = "less -c";

private define py_whitespace(cnt)
{
  if ( get_blocal_var("py_use_tab") )
    loop (cnt / TAB) insert_char('\t');
  else
    insert_spaces (cnt);
}

private define py_indent_after_chars()
{
  eol();
  if (bfind_char(':') || bfind_char('{') || bfind_char('[') || bfind_char('(')) 
  {
    go_right(1);
    skip_white();
    if (eolp() or looking_at_char('#'))
      return 1;
  }
  return 0;
}

private define py_is_closing_delim()
{
  bol_skip_white();
  if (looking_at("}") || looking_at("]") || looking_at(")")) 
      return 1;
  return 0;
}

private define py_endblock_cmd()
{
  bol_skip_white();
  push_mark();
  skip_chars("a-z");
  return is_list_element("return,raise,break,pass,continue",
                         bufsubstr(), ',') > 0;
}

private define py_line_starts_subblock()
{
  bol_skip_white();
  if (looking_at("else") or
      looking_at("elif")  or
      looking_at("except")  or
      looking_at("finally"))
    return 1;
  return 0;
}

private define py_line_starts_block()
{
  bol_skip_white();
  if (looking_at("if") or
      looking_at("try") or
      py_line_starts_subblock())
    return 1;
  return 0;
}

private define py_indent_calculate()
{  % return the indentation of the previous python line
  variable col = 0;
  variable subblock = 0;
  
  EXIT_BLOCK
  {
    pop_spot ();
  }
  
  % check if current line starts a sub-block
  subblock = py_line_starts_subblock();
  push_spot();
  
  if (py_is_closing_delim())
  {
    variable ch = what_char();
    
    if (1 == find_matching_delimiter(ch))
    {
      bol_skip_white();
      col = _get_point();
    }
    
    return col;
  }
  
  % go to previous non blank line
  bol ();
  ifnot (re_bsearch ("[^ \t\n]"))
  {
    pop_spot();
    return 0;
  }

  bol_skip_white();
  col = what_column() - 1;
  
  variable indent;

  if ( get_blocal_var("py_use_tab") )
    indent = TAB;
  else
    indent = Py_Indent_Level;
  
  if (py_indent_after_chars())
    col += indent;
  if (py_endblock_cmd() or (subblock and not py_line_starts_block()))
    col -= indent;

  return col;
}

define py_indent_line()
{
  variable col;
  
  col = py_indent_calculate();
  bol_trim ();
  py_whitespace( col );
}

define py_electric_colon()
{
  variable i;
  insert(":");
  push_spot();
  if (py_line_starts_subblock())  % Only dedents on colon
  {
    pop_spot();
    i = what_column();
    bol_skip_white();
    i = i - what_column();
    if (py_indent_calculate() < what_column()) % Ensure dedent only
      py_indent_line();
    bol_skip_white();
    goto_column( i + what_column() );
  }
  else
    pop_spot();
}

define py_backspace_key()
{
  variable col;
  
  col = what_column();
  push_spot();
  bskip_white();
  if (bolp() and (col > 1))
  {
    pop_spot();
    if ( blooking_at("\t") )
    {
      go_left (1);
      del();
    }
    else
    {
      bol_trim ();
      col--;
      if (col mod Py_Indent_Level == 0)
        col--;
      py_whitespace ( (col / Py_Indent_Level) * Py_Indent_Level );
    }
  }
  else
  {
    pop_spot();
    call("backward_delete_char_untabify");
  }
}

define py_shift_line_right()
{
  variable times = prefix_argument(1);
  bol_skip_white();
  py_whitespace(Py_Indent_Level*times);
}

define py_shift_region_right()
{
  variable times = prefix_argument(1);
  check_region (1);           %  spot_pushed, now at end of region
  variable n = what_line ();
  pop_mark_1 ();
  loop (n - what_line ())
  {
    set_prefix_argument(times);
    py_shift_line_right();
    go_down_1 ();
  }
  pop_spot();
}

define py_shift_right()
{
   push_spot();
   if (markp()) {
      py_shift_region_right();
   } else {
      py_shift_line_right();
   }
   pop_spot();
}

define py_shift_line_left()
{
  variable times = prefix_argument(1);
  bol_skip_white();
  if (what_column() > Py_Indent_Level*times)
  {
    if ( get_blocal_var("py_use_tab") )
    {
      go_left (times);
      deln(times);
    }
    else
    {
      push_mark();
      goto_column(what_column() - Py_Indent_Level*times);
      del_region();
    }
  }
}

define py_shift_region_left()
{
  variable times = prefix_argument(1);
  
  check_region (1);
  variable n = what_line ();
  pop_mark_1 ();
  loop (n - what_line ())
  {
    set_prefix_argument (times);
    py_shift_line_left();
    go_down_1 ();
  }
  pop_spot();
}

define py_shift_left() {
   push_spot();
   if (markp()) {
      py_shift_region_left();
   } else {
      py_shift_line_left();
   }
   pop_spot();
}

define py_newline_and_indent()
{
  push_spot();
  bol_skip_white();
  variable p = _get_point();
  
  if (looking_at(Cmt_Char_Beg)) % continued comments
  {
    pop_spot();
    
    ifnot (looking_at(Cmt_Char_Beg))
    {
      insert("\n");
      insert_spaces(p);
      insert(Cmt_Char_Beg);
      return;
    }
  }
  
  pop_spot();
  newline();
  py_indent_line();
}

% Mark word at point. It is used for the py_help() function. It also
% marks operators, as there are help pages for those also.
private define py_mark_word()
{
  variable word = "";
  variable wchars = "-A-Za-z_=\+-\*@<>%/&"; % also help on operators

  push_spot();

  if (re_looking_at("[$wchars]"$))
  {
    bskip_chars(wchars);
    push_mark();
    skip_chars(wchars);
  }
  else
  {
    skip_white();

    if (eolp())
    {
      bskip_white();
      bskip_chars(wchars);
    }
    else
      skip_chars(wchars);
  }
  
  if (markp())
    word = bufsubstr();

  pop_spot();

  return word;
}

% The following six variables are for indexing and coloring
% lines with errors/warnings identified by ruff.
private variable Py_Check_Err_Msgs = String_Type[0];
private variable Py_Check_Lines = Int_Type[0];
private variable Py_Check_Linenos = Int_Type[0];
private variable Py_Check_Err_Cols = Int_Type[0];
private variable Py_Check_Error_Color = color_number("preprocess");
private variable Py_Check_Error_Color_Crit = color_number("error");

% Reset the error index and remove line coloring.
private define py_check_reset()
{
  push_spot_bob();
  do
  {
    if (get_line_color == Py_Check_Error_Color ||
        get_line_color == Py_Check_Error_Color_Crit)
    {
      set_line_color(0);
    }
  }
  while (down(1));

  pop_spot();
  Py_Check_Lines = Int_Type[0];
  Py_Check_Linenos = Int_Type[0];
  Py_Check_Err_Cols = Int_Type[0];
  Py_Check_Err_Msgs = String_Type[0];
  set_blocal_var(0, "Py_Checked");
  call("redraw");
}

% This must be sure to write the whole buffer and not a marked region
private define py_write_buffer_to_tmpfile()
{
  variable tmpfile = make_tmp_file("ruff_tmp");
  variable str = "";
  
  push_spot_bob();
  push_mark_eob();
  str = bufsubstr();
  pop_spot();

  if (-1 == write_string_to_file(str, tmpfile))
    throw WriteError, "could not write buffer to $file"$;

  return tmpfile;
}

% Color and index lines identified by "ruff check" as having errors/warnings.
% Critical errors are colored in the color of the error color object, others
% are colored in the color of the preprocessor object.
private define py_color_error_lines()
{
  variable ruff = search_path_for_file (getenv("PATH"), "ruff");
  variable errmsg = "", i = 0, line, col, lineno, lineno_col, fp, cmd, tmpfile;

  if (ruff == NULL)
    throw RunTimeError, "ruff program not found";

  py_check_reset();
  tmpfile = py_write_buffer_to_tmpfile();
  cmd = "$ruff check $tmpfile"$;
  fp = popen (cmd, "r");
  Py_Check_Lines = fgetslines(fp);
  () = pclose (fp);
  () = delete_file(tmpfile);

  if (is_substr(Py_Check_Lines[0], "All checks passed"))
    return flush("All checks passed");

  push_spot();

  _for i (0, length(Py_Check_Lines) - 1, 1)
  {
    line = Py_Check_Lines[i];
    lineno_col = pcre_matches(":(\\d+):(\\d+)", line);

    if (lineno_col == NULL) continue;

    lineno = integer(lineno_col[1]);

    if (lineno == NULL) continue;

    errmsg = Py_Check_Lines[i - 1];
    Py_Check_Err_Msgs = [Py_Check_Err_Msgs, errmsg];
    col = integer(lineno_col[2]);
    goto_line(lineno);

    if (string_match(errmsg, "^invalid", 1) || string_match(errmsg, "^error", 1))
      set_line_color(Py_Check_Error_Color_Crit);
    else
      set_line_color(Py_Check_Error_Color);

    Py_Check_Linenos = [Py_Check_Linenos, lineno];
    Py_Check_Err_Cols = [Py_Check_Err_Cols, col];
  }

  pop_spot();
  set_blocal_var(1, "Py_Checked");
  call("redraw");
  vmessage("Found %d issues", length(Py_Check_Err_Msgs));
}

define py_exec_any_cmd()
{
  variable cmd = __push_list(__pop_list(_NARGS));
  () = run_program(cmd);
}

private variable Last_Cmd = Python;

% Execute a command on buffer or region. Allows for user interaction.
define py_exec_cmd_on_buffer_or_region()
{
  variable str = "", tmpfile = "", cmd = "", opts = "", cmd_line = "";
  
  ifnot (markp())
    tmpfile = py_write_buffer_to_tmpfile();
  else
  {
    str = bufsubstr();
    tmpfile = make_tmp_file("py_exec_reg");
    
    if (-1 == write_string_to_file(str, tmpfile))
      throw WriteError, "could not write buffer to $tmpfile"$;
  }
  
  cmd = read_string_with_completion("Execute command:", Last_Cmd, "");
  ifnot (strlen(cmd)) return;
  opts = read_mini("additional arguments to \"$cmd\":"$, "", "");
  
  Last_Cmd = cmd;

  try
  {
    cmd_line =
      "clear; echo 'output from \"$cmd $opts\":\n'; "$ +
      "$cmd $opts $tmpfile; "$ +
      "echo \"\n\033[7mPress <enter> to return to editor ...\033[0m\"; " +
      "read; clear";
  
    () = run_program("$cmd_line"$);
  }
  finally
    () = remove(tmpfile);
}
  
% Format buffer or possibly fix some errors/warnings with ruff. Provide
% a preview of possible changes before accepting them.
private define py_format_or_fix(which)
{
  variable obj = Struct_Type, e = 0, msg = "", tmpfile = "";
  variable backup_file = sprintf("/tmp/%s~", whatbuf());
  variable outfile = make_tmp_file("ruff_out");
  variable lineno = what_line();

  tmpfile = py_write_buffer_to_tmpfile();

  if (-1 == copy_file (tmpfile, backup_file))
    throw RunTimeError, "could not back up file";
  
  try
  {
    % check for critical errors
    obj = new_process (["ruff", "check", "--select=E9", tmpfile];
                       stdout = "/dev/null", stderr = "/dev/null");
    
    e = obj.wait().exit_status;
    
    if (e > 0)
      throw RunTimeError, "File contains critical errors, run py_check first"$;
    
    % the following two commands may modify the tmpfile
    if (which == "format")
      obj = new_process (["ruff", "format", tmpfile];
                         stdout = "/dev/null", stderr = "/dev/null");

    if (which == "fix")
      obj = new_process (["ruff", "check", "--fix", "--unsafe-fixes", tmpfile];
                         stdout = "/dev/null", stderr = "/dev/null");
      
    % check for critical errors once more on the now possibly changed file ...
    obj = new_process (["ruff", "check", "--select=E9", tmpfile];
                       stdout = "/dev/null", stderr = "/dev/null");

    e = obj.wait().exit_status;

    sleep(.1);

    if (e == 0)
    {
      obj = new_process (["diff", "-u", tmpfile, backup_file];
                         stdout = outfile, stderr = "/dev/null");

      e = obj.wait().exit_status;

      if (e == 0) % diff return code 0 = unchanged file
      {
        msg = "File was unchanged";
        return;
      }
      else
      {
        py_exec_any_cmd("cat $outfile | $Py_Pager"$);

        ifnot (get_y_or_n("okay to apply changes"))
        {
          msg = "aborting changes";
          return;
        }

        erase_buffer();
        () = insert_file(tmpfile);
        goto_line(lineno); % this won't necessarily be very precise.
        msg = "Old file backed up as $backup_file"$;
      }
    }
    else
      throw RunTimeError, "Command failed, nothing done! Run py_check";
  }
  finally
  {
    flush(msg);
    () = remove(tmpfile);
    () = remove(outfile);
  }
}

define py_check()
{
  py_color_error_lines();
}

define py_fix()
{
  if (get_y_or_n("Fix some errors/warnings with ruff"))
    py_format_or_fix("fix");
}

define py_format()
{
  if (get_y_or_n("Format buffer with ruff"))
    py_format_or_fix("format");
}

private variable Ruff_Err_Code = NULL;

% Jump back or forth to error lines. Both directions wrap around buffer.
define py_goto_next_or_prev_error_entry(dir)
{
  variable err_col, err_lineno, err_msg = "", this_line = what_line();
  variable i = 0;
  
  Ruff_Err_Code = NULL;

  ifnot (1 == get_blocal_var("Py_Checked"))
    py_check();

  try
  {
    if (length(Py_Check_Linenos) > 1)
    {
      if (dir < 0) % find index position of previous error line
        i = where(this_line > Py_Check_Linenos)[-1];
      else if (dir > 0)
        i = where(this_line < Py_Check_Linenos)[0];
      else
        i = where(this_line == Py_Check_Linenos)[0];
    }
  }
  catch IndexError:
  {
    if (dir == -1 && i == 0) % if top entry reached, wrap to bottom entry
      return goto_line(Py_Check_Linenos[-1]);
  }
  
  err_lineno = Py_Check_Linenos[i];
  err_col = Py_Check_Err_Cols[i];
  goto_line(err_lineno);
  () = goto_column_best_try(err_col);
  err_msg = Py_Check_Err_Msgs[i];
  Ruff_Err_Code = pcre_matches("\\w+", err_msg)[0];
  call("redraw");
  flush(strtrim(err_msg));
}

% Show ruff error/warning explanation in a pager
private define py_show_error_descr()
{
  if (Ruff_Err_Code == NULL)
    py_goto_next_or_prev_error_entry(0);
  
  py_exec_any_cmd("ruff rule $Ruff_Err_Code | $Py_Pager"$);
}

% Show help for word at point or for a typed in word. If placed on a line
% colored by py_check(), show the error code's description.
define py_help()
{
  variable word = py_mark_word(), cmd = "";
  
  if (get_line_color == Py_Check_Error_Color ||
      get_line_color == Py_Check_Error_Color_Crit)
  {
    py_show_error_descr();
    return;
  }

  % empty word launches python's help utility in interactive window
  word = read_mini("Help for:", "", word);

  if (strlen(word))
    word = "'$word'"$; % word must be in single quotes
  
  cmd =
    "clear; $Python -c \"help($word)\" 2>/dev/null; "$ +
    "echo \"\n\033[7mPress <enter> to return to editor ...\033[0m\"; " +
    "read; clear";

  () = run_program(cmd);
}
  
define py_reindent() {
  % Reindents a (correctly) indented buffer using the current
  % value of Py_Indent_Level.
  % Warning: Current version can be fooled by implicit or explicit
  %   continuation lines.
  variable indent_level = Int_Type[64];
  %variable indent_level = create_array('i', 64, 1);
  variable level = -1;
  variable current_indent = -1;
  variable errmsg, i, col, ignore, oldlevel;
  
  indent_level[*] = -1;
  bob();
  do {
    bol_skip_white();
    ignore = looking_at_char('#') or eolp();
    if (ignore) continue;  % skip comments and blank lines
    col = what_column() - 1;
    oldlevel = level;    % save current level
    if (col > current_indent) {  % indenting
      level++;
    } else if (col < current_indent) {  % dedent
      while ((level > 0) and (indent_level[level] > col)) {
        indent_level[level] = -1;  % clear current level setting
        level--;
      }
    }
    if ((indent_level[level] != -1) and (indent_level[level] != col)) {
      % Indent is wrong.  Hopefully it's a continuation line.
      level = oldlevel;  % reset level
      bol_trim();
      py_whitespace(level * Py_Indent_Level + (col - current_indent));
    } else {
      current_indent = col;
      indent_level[level] = col;
      bol_trim();
      py_whitespace(level * Py_Indent_Level);
    }
  } while (down(1) == 1);
}

define py_reindent_region()
{
  narrow();
  py_reindent();
  widen();
}

#ifdef MSWINDOWS
define py_help_on_word()
{
   variable tag = "0-9A-Z_a-z";

   push_spot ();
   skip_white ();
   bskip_chars (tag);
   push_mark ();
   skip_chars (tag);
   tag = bufsubstr ();		% leave on the stack
   pop_spot ();
   message( strcat("Help on ", tag) );
   msw_help( getenv("PYLIBREF"), tag, 0);
}

#endif

create_syntax_table ($1);
define_syntax ("#", "", '%', $1);    % comments
define_syntax ("([{", ")]}", '(', $1);    % delimiters
define_syntax ('"', '"', $1);      % quoted strings
define_syntax ('\'', '"', $1);      % quoted strings
%define_syntax("\"\"\"","\"\"\"", '%', $1);
%define_syntax ('\'', '\'', $1);      % quoted characters
define_syntax ('\\', '\\', $1);      % continuations
define_syntax ("0-9a-zA-Z_", 'w', $1);    % words
define_syntax ("-+0-9a-fA-FjJlLxX.", '0', $1);  % Numbers
define_syntax (",;.:", ',', $1);    % punctuation
define_syntax ("%-+/&*=<>|!~^`", '+', $1);  % operators
set_syntax_flags ($1, 0);      % keywords ARE case-sensitive

private variable Kws =
  `if,in,is,or,and,def,del,for,not,try,elif,else,exec,from,pass,break,class,
   print,raise,while,yield,assert,except,global,import,lambda,return,finally,
   continue,None,as,with,async,match,await,nonlocal,case`;

Kws = strtok(Kws, ",");
Kws = strtrim(Kws);

% Type 1 keywords (actually these are what's in __builtins__)
private variable Builtins =
  `id,set,sum,zip,abs,chr,cmp,dir,hex,int,len,map,max,min,oct,ord,pow,str,
   aiter,all,anext,any,ascii,bin,breakpoint,bytearray,bytes,memoryview,next,
   True,bool,dict,exit,file,help,iter,list,quit,eval,hash,long,open,repr,type,vars,
   False,slice,super,apply,float,input,range,round,tuple,buffer,intern,object,
   sorted,unichr,coerce,divmod,filter,locals,reduce,reload,xrange,OSError,
   Warning,complex,credits,license,unicode,IOError,__doc__,compile,delattr,
   getattr,globals,hasattr,setattr,Ellipsis,TabError,property,reversed,EOFError,
   KeyError,__name__,callable,execfile,__call__,Exception,__debug__,copyright,
   enumerate,frozenset,NameError,TypeError,raw_input,basestring,isinstance,
   issubclass,IndexError,SystemExit,ValueError,__import__,LookupError,
   UserWarning,classmethod,AccessError,ImportError,MemoryError,SyntaxError,
   SystemError,UnicodeError,staticmethod,RuntimeError,FutureWarning,
   StandardError,StopIteration,SyntaxWarning,ConflictError,OverflowError,
   AssertionError,NotImplemented,ReferenceError,RuntimeWarning,AttributeError,
   AssertionError,ArithmeticError,OverflowWarning,EnvironmentError,
   IndentationError,UnboundLocalError,KeyboardInterrupt,ZeroDivisionError,
   DeprecationWarning,FloatingPointError,UnicodeDecodeError,UnicodeEncodeError,
   NotImplementedError,UnicodeTranslateError,PendingDeprecationWarning,
   BaseException,BaseExceptionGroup,GeneratorExit,BufferError,ExceptionGroup,
   ModuleNotFoundError,BlockingIOError,ChildProcessError,ConnectionError,
   BrokenPipeError,ConnectionAbortedError,ConnectionRefusedError,
   ConnectionResetError,FileExistsError,FileNotFoundError,InterruptedError,
   IsADirectoryError,NotADirectoryError,PermissionError,ProcessLookupError,
   TimeoutError,PythonFinalizationError,RecursionError,StopAsyncIteration,
   BytesWarning,EncodingWarning,ImportWarning,ResourceWarning,UnicodeWarning`;

Builtins = strtok(Builtins, ",");
Builtins = strtrim(Builtins);

private variable Methods =
  `__add__,__contains__,__eq__,__format__,__ge__,__getitem__,__getnewargs__,
   __gt__,__hash__,__iter__,__le__,__len__,__lt__,__mod__,__mul__,__ne__,
   __repr__,__rmod__,__rmul__,__sizeof__,__str__,capitalize,casefold,center,
   count,encode,endswith,expandtabs,find,format,format_map,index,isalnum,
   isalpha,isascii,isdecimal,isdigit,isidentifier,islower,isnumeric,isprintable,
   isspace,istitle,isupper,join,ljust,lower,lstrip,partition,removeprefix,
   removesuffix,replace,rfind,rindex,rjust,rpartition,rsplit,rstrip,split,
   splitlines,startswith,strip,swapcase,title,translate,upper,zfill,__new__,
   maketrans`;

Methods = strtok(Methods, ",");
Methods = strtrim(Methods);

private define py_add_kws_to_table(kws, tbl, n)
{
  variable kws_i, i;

  _for i (1, 48, 1) % 48 is the keyword length limit.
  {
    kws_i = kws[where(strlen(kws) == i)];
    kws_i = kws_i[array_sort (kws_i)];
    kws_i = strtrim(kws_i);
    kws_i = strjoin(kws_i, "");

    ifnot (strlen (kws_i)) continue;

    () = add_keywords($1, kws_i, i, n);
  }
}

#ifdef HAS_DFA_SYNTAX
%%% DFA_CACHE_BEGIN %%%
private define setup_dfa_callback (name)
{
  dfa_enable_highlight_cache("python.dfa", name);
  dfa_define_highlight_rule("\"\"\".+\"\"\"", "string", name);  % long string (""")
  dfa_define_highlight_rule("'''.+'''", "string", name);  % long string (''')
  dfa_define_highlight_rule("\"[^\"]*\"", "string", name);  % normal string
  dfa_define_highlight_rule("'[^']*'", "string", name);    % normal string
  dfa_define_highlight_rule("#.*", "comment", name);    % comment
  dfa_define_highlight_rule("[A-Za-z_][A-Za-z_0-9]*", "Knormal", name); % identifier
  dfa_define_highlight_rule("[1-9][0-9]*[lL]?", "number", name);  % decimal int
  dfa_define_highlight_rule("0[0-7]*[lL]?", "number", name);    % octal int
  dfa_define_highlight_rule("0[xX][0-9a-fA-F]+[lL]?", "number", name);  % hex int
  dfa_define_highlight_rule("[1-9][0-9]*\\.[0-9]*([Ee][\\+\\-]?[0-9]+)?",
                            "number", name);        % float n.[n]
  dfa_define_highlight_rule("0?\\.[0-9]+([Ee][\\+\\-]?[0-9]+)?",
                            "number", name);        % float [n].n
  dfa_define_highlight_rule("[ \t]+", "normal", name);
  dfa_define_highlight_rule("[\\(\\[{}\\]\\),:\\.\"`'=;]", "delimiter", name);
  dfa_define_highlight_rule("[\\+\\-\\*/%<>&\\|\\^~]", "operator", name); % 1 char
  dfa_define_highlight_rule("<<|>>|==|<=|>=|<>|!=", "operator", name);    % 2 char
  
  % Flag badly formed numeric literals or identifiers.  This is more effective
  % if you change the error colors so they stand out.
  dfa_define_highlight_rule("[1-9][0-9]*[lL]?[0-9A-Za-z\\.]+", "error", name);  % bad decimal
  dfa_define_highlight_rule("0[0-7]+[lL]?[0-9A-Za-z\\.]+", "error", name); % bad octal
  dfa_define_highlight_rule("0[xX][0-9a-fA-F]+[lL]?[0-9A-Za-z\\.]+", "error", name); % bad hex
  dfa_define_highlight_rule("\\.[0-9]+([Ee][\\+\\-]?[0-9]+)?[A-Za-z]+", "error", name);  % bad float
  dfa_define_highlight_rule("[A-Za-z_][A-Za-z_0-9]*\\.[0-9]+[A-Za-z]*", "error", name); % bad identifier
  
  dfa_build_highlight_table(name);
}
dfa_set_init_callback (&setup_dfa_callback, $1);
%%% DFA_CACHE_END %%%
#endif

% List all function definitions in a submenu and jump to them with a click.
private define functions_popup_callback(popup)
{
  variable fname, fnames, lineno, linenos_hash = Assoc_Type[Int_Type];
  push_spot_bob;
  
  while (re_fsearch("^def .*$"))
  {
    fname = regexp_nth_match(0);
    linenos_hash[fname] = what_line();
    eol();
  }
  
  fnames = assoc_get_keys(linenos_hash);
  fnames = fnames[array_sort(fnames)];
  
  foreach fname (fnames)
  {
    lineno = linenos_hash[fname];
    menu_append_item(popup, fname, &goto_line, lineno);
  }
  
  pop_spot;
}

private define py_menu(menu)
{
  menu_append_popup(menu, "&Functions");
  menu_set_select_popup_callback (strcat (menu, ".&Functions"),
                                  &functions_popup_callback);

  menu_append_item (menu, "Shift Line Right", "py_shift_line_right");
  menu_append_item (menu, "Shift Line Left", "py_shift_line_left");
  menu_append_item (menu, "Shift Region Right", "py_shift_region_right");
  menu_append_item (menu, "Shift Region left", "py_shift_region_left");
  menu_append_item (menu, "Check Buffer With Ruff Linter", "py_check");
  menu_append_item (menu, "Format Buffer With Ruff", "py_format");
  menu_append_item (menu, "Fix Some Errors With Ruff", "py_fix");
  menu_append_item (menu, "Help for Word or Error", "py_help");
  menu_append_item (menu, "Go to Next Line With Issue", "py_goto_next_or_prev_error_entry\(1\)");
  menu_append_item (menu, "Go to Previous Line With Issue", "py_goto_next_or_prev_error_entry\(-1\)");
  menu_append_item (menu, "Execute Cmd on Code in Region/Buffer", "py_exec_cmd_on_buffer_or_region");
}

%!%+
%\function{python_mode}
%\synopsis{python_mode}
%\usage{python_mode ()}
%\description
% A major mode for editing python files.
%
% The following keys have python specific bindings:
%#v+
% DELETE deletes to previous indent level
% TAB indents line
% ^C> shifts line or region right
% ^C< shifts line or region left
% ^C^C executes the region, or the buffer if region not marked.
% ^C\t reindents the region
% :    colon dedents appropriately
%#v-
% Hooks: \var{python_mode_hook}
%
%\seealso{Py_Indent_Level}
%\seealso{set_mode, c_mode}
%!%-
define python_mode ()
{
  if (NULL == search_path_for_file(getenv("PATH"), Python))
    throw RunTimeError, "Python not found"$;

  define_blocal_var("Py_Checked", 0);
  create_blocal_var("py_use_tab");
  set_blocal_var(Py_Indent_Level == TAB, "py_use_tab");
  push_spot();
  bob();
  do
  {
    skip_white();
    if ( looking_at("\"\"\"") )
    {
      go_right (1);
      () = fsearch("\"\"\"");
    }
    else ifnot (looking_at_char('#') or eolp() or what_column() == 1)
    {
      bol();
      set_blocal_var(looking_at_char('\t'), "py_use_tab");
      break;
    }
  }
  while (down(1));
  pop_spot();
  
  set_mode ($1, 0x4); % flag value of 4 is generic language mode
  use_keymap($1);
  py_add_kws_to_table(Kws, $1, 0);
  py_add_kws_to_table(Builtins, $1, 1);
  py_add_kws_to_table(Methods, $1, 1);
  mode_set_mode_info ($1, "init_mode_menu", &py_menu);
  set_buffer_hook ("indent_hook", "py_indent_line");
  set_buffer_hook ("newline_indent_hook", "py_newline_and_indent");
  use_syntax_table ($1);
  wrap_mode();
  run_mode_hooks ("python_mode_hook");
}
