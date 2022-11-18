% sh.sl - a mode for the Jed editor to facilitate the editing of shell scripts.
% Author: Morten Bo Johansen <listmail at mbjnet dot dk>
% License: https://www.gnu.org/licenses/gpl-3.0.en.html
require("pcre");
require("keydefs");
autoload("add_keywords", "syntax");

% User defined variable of how much indentation is wanted.
custom_variable("SH_Indent", 2);

% User defined variable of browser
custom_variable("SH_Browser", "lynx");

% User defined variable of automatic code block insertion
custom_variable("SH_Expand_Kw_Syntax", 0);

private variable
  Mode = "SH",
  Version = 0.2,
  SH_Indent_Kws,
  SH_Indent_Kws_Re,
  SH_Do_Done_Kws,
  SH_Do_Done_Kws_Re,
  SH_Shellcheck_Error_Color = color_number("preprocess"),
  SH_Kws_Hash = Assoc_Type[String_Type, ""],
  SH_Indent_Hash = Assoc_Type[String_Type, ""];

% Keywords that trigger some indentation rule
SH_Indent_Kws = ["if","fi","else","elif","for","while","case","esac","do",
                 "done","select","until","then"];

% OR'ed expression of $SH_Indent_Kws
SH_Indent_Kws_Re = strjoin(SH_Indent_Kws, "|");

% Regular expression for keywords with some added indentation triggers
% such as parentheses and braces.
SH_Indent_Kws_Re = strcat("^.*?\\b(", SH_Indent_Kws_Re, ")\\b(?:.*(\\b(do|if|fi)\\b))?", % match keywords only as whole words
                          "|^\\s*\\beval\\b", % 'eval' at begin of line
                          "|^\\s*(\})\\s*#?", % right brace at begin of line with some blank space allowed
                          "|({)\\s*$", % opening left brace in functions
                          "|^[^$]*({)\\s*#", % same but allow for trailing comment
                          "|^\\s*\\bdo\\b\\s*", % 'do' on begin of line
                          "|^\\s*\\)", % right parenthesis at begin of line
                          "|\\(\\s*$" % match an opening left parenthesis
                         );

% Keywords that begin a do..done block
SH_Do_Done_Kws = ["while","for","select","until","do"];
SH_Do_Done_Kws_Re = strjoin(SH_Do_Done_Kws, "|");
SH_Do_Done_Kws_Re = strcat ("^\\s*\\b(", SH_Do_Done_Kws_Re, ")\\b");

% Associative array that will be used to position its paired keywords
% to each other.
SH_Kws_Hash["case_cond"] = "case";
SH_Kws_Hash["esac"] = "case";
SH_Kws_Hash["done"] = "do";
SH_Kws_Hash[")"] = "(";
SH_Kws_Hash["}"] = "{";
SH_Kws_Hash["fi"] = "if";
SH_Kws_Hash["else"] = "if";
SH_Kws_Hash["elif"] = "if";

% Associative array to insert and expand syntaxes for its keys
SH_Indent_Hash["if"] = " @; then\n\nfi";
SH_Indent_Hash["elif"] = " @; then\n\nelse\n\nfi\n";
SH_Indent_Hash["for"] = " @ in ; do\n\ndone";
SH_Indent_Hash["while"] = " @; do\n\ndone";
SH_Indent_Hash["select"] = " @ in ; do\n\ndone";
SH_Indent_Hash["until"] = " @; do\n\ndone";
SH_Indent_Hash["case"] = " $@ in\n*)\n;;\n*)\n;;\nesac";

% For highlighting
private variable SH_Kws = [SH_Indent_Kws, ["!","in",";;","time","do","END","EOF"]];

% For highlighting. These should cover korn, posix, bourne, bash and zsh?
private variable SH_Builtins =
  `exec,shift,.,exit,times,break,export,trap,continue,readonly,wait,eval,
   return,alias,fg,print,ulimit,bg,getopts,pwd,umask,cd,jobs,read,unalias,
   command,setgroups,echo,let,setsenv,test,whence,fc,hash,set,type,
   unset,@,breaksw,chdir,default,dirs,end,endif,endsw,foreach,glob,goto,
   hashstat,history,jobs,kill,limit,login,logout,nice,nohup,notify,onintr,
   popd,pushd,rehash,setenv,source,stop,suspend,unhash,unlimit,
   unsetenv,newgrp,typeset,readarray,printf,mapfile,local,help,enable,
   declare,caller,builtin,bind,autoload,bindkey,bye,cap,clone,comparguments,
   compcall,compctl,compdescribe,compfiles,compgroups,compquote,comptags,
   comptry,compvalues,disable,disown,echotc,echoti,emulate,false,functions,
   getcap,getln,log,noglob,pushln,sched,setcap,setopt,shopt,stat,true,unfunction,
   unsetopt,vared,where,which,zcompile,zformat,zftp,zle,zmodload,zparseopts,
   zprof,zpty,zregexparse,zsocket,zstyle,ztcp`;

SH_Builtins = strtrim(strchop(SH_Builtins, ',', 0));

private variable SH_Variables =
  `allow_null_glob_expansion,auto_resume,BASH,BASH_ENV,BASH_VERSINFO,
   BASH_VERSION,cdable_vars,COMP_CWORD,COMP_LINE,COMP_POINT,
   COMP_WORDS,COMPREPLY,DIRSTACK,ENV,EUID,FCEDIT,FIGNORE,IFS,
   FUNCNAME,glob_dot_filenames,GLOBIGNORE,GROUPS,histchars,
   HISTCMD,HISTCONTROL,HISTFILE,HISTFILESIZE,HISTIGNORE,
   history_control,HISTSIZE,hostname_completion_file,HOSTFILE,HOSTTYPE,
   IGNOREEOF,ignoreeof,INPUTRC,LINENO,MACHTYPE,MAIL_WARNING,noclobber,
   nolinks,notify,no_exit_on_failed_exec,NO_PROMPT_VARS,OLDPWD,OPTERR,
   OSTYPE,PIPESTATUS,PPID,POSIXLY_CORRECT,PROMPT_COMMAND,PS3,PS4,
   pushd_silent,PWD,RANDOM,REPLY,SECONDS,SHELLOPTS,SHLVL,TIMEFORMAT,
   TMOUT,UID,BAUD,bindcmds,cdpath,DIRSTACKSIZE,fignore,FIGNORE,fpath,
   HISTCHARS,hostcmds,hosts,HOSTS,LISTMAX,LITHISTSIZE,LOGCHECK,mailpath,
   manpath,NULLCMD,optcmds,path,POSTEDIT,prompt,PROMPT,PROMPT2,PROMPT3,
   PROMPT4,psvar,PSVAR,READNULLCMD,REPORTTIME,RPROMPT,RPS1,SAVEHIST,SPROMPT,
   STTY,TIMEFMT,TMOUT,TMPPREFIX,varcmds,watch,WATCH,WATCHFMT,WORDCHARS,ZDOTDIR`;

SH_Variables = strtrim(strchop(SH_Variables, ',', 0));

% Add an array of keywords to a syntax table for highlighting
private define sh_add_kws_to_table(kws, tbl, n)
{
  variable kws_i, i;

  _for i (1, 48, 1) % 48 is the keyword length limit.
  {
    kws_i = kws[where(strlen(kws) == i)];
    kws_i = kws_i[array_sort (kws_i)];
    kws_i = strtrim(kws_i);
    kws_i = strjoin(kws_i, "");

    ifnot (strlen (kws_i)) continue;

    () = add_keywords(Mode, kws_i, i, n);
  }
}

create_syntax_table (Mode);

private define sh_setup_syntax()
{
  variable bg;
  (, bg) = get_color("normal"); % get the current background color
  set_color("keyword", "red", bg);
  set_color("operator", "yellow", bg);
  define_syntax("#", "", '%', Mode); % comments
  define_syntax("([{", ")]}", '(', Mode); % delimiters
  define_syntax('"', '"', Mode);
  define_syntax('`', '"', Mode);
  define_syntax('\'', '"', Mode);
  define_syntax ('\\', '\\', Mode);
  define_syntax("-a-zA-Z.:@!;", 'w', Mode);    % words
  define_syntax("-+0-9a-fA-F.xX", '0', Mode); % Numbers
  define_syntax(",;:.", ',', Mode);
  define_syntax("[]-+/&*=<>|!~^\\", '+', Mode);
  define_syntax ("-a-zA-Z0-9_", 'w', Mode);
  use_syntax_table(Mode);
  sh_add_kws_to_table(SH_Kws, Mode, 0);
  sh_add_kws_to_table(SH_Builtins, Mode, 1);
  sh_add_kws_to_table(SH_Variables, Mode, 1);
}

private define sh_line_as_str()
{
  push_spot(); line_as_string(); pop_spot();
}

% Matches pcre style regex pattern in current line. Returns matches as
% an array with the same return value as pcre_matches()
private define sh_re_match_line (re)
{
  return pcre_matches(re, sh_line_as_str());
}

% Return the beginning column of a keyword
private define return_kw_col (kw)
{
  variable p, pos = 0;

  kw = strtrim(kw);

  if (any(kw == SH_Indent_Kws))
    p = pcre_compile("\\b$kw\\b"$);
  else
    p = pcre_compile("\\$kw"$);

  if (pcre_exec(p, sh_line_as_str()))
    return pcre_nth_match (p, 0)[0];

  return 0;
}

% Use the parse_to_point() function to determine if keyword is
% legitimate or a false positive within a string/comment. Returns
% the value of parse_to_point().
private define sh_is_kw_in_string_or_comment(kw)
{
  ifnot (NULL == sh_re_match_line("^[^#].*\\$\{?#")) return 0; % $#, ${# not cmts
  ifnot (NULL == sh_re_match_line("^\\becho\\b")) return -1; % arg to 'echo' may not be stringified
  variable col = return_kw_col(kw);
  push_spot_bol();
  goto_column(col+1);
  parse_to_point; % on stack
  pop_spot();
}

private define sh_is_line_continued()
{
  try
  {
    push_spot (); go_up_1();
    ifnot (NULL == sh_re_match_line("\\\\$")) return 1;

    return 0;
  }
  finally pop_spot();
}

private define sh_indent_spaces (n)
{
  bol_trim(); insert_spaces(n);
}

% A line like, "abc)" is presumably a case/esac condition but could
% also match a left parenthesis on a previous line. It will return a
% positive integer in that case.
private define sh_case_cond_is_end_par ()
{
  variable par_n = 0;
  push_spot();
  ifnot (NULL == sh_re_match_line(".*\\(.*(*SKIP)(*F)|\\S\\)"))
  {
    while (up(1))
    {
      ifnot (NULL == sh_re_match_line(".*\\(.*(*SKIP)(*F)|^.*?(\\))+")) break;
      ifnot (NULL == sh_re_match_line(".*\\).*(*SKIP)(*F)|^.*?(\\()+"))
      {
        () = ffind("(");
        if (sh_is_kw_in_string_or_comment("(")) break;
        par_n++;
      }
    }
  }

  pop_spot();
  return par_n;
}

% Return the keyword on the current line
private define sh_get_indent_kw ()
{
  variable kw = NULL;

  % one line do..done blocks
  ifnot (NULL == sh_re_match_line(SH_Do_Done_Kws_Re + ".*done\\s*#?"))
    return NULL;

  % if..fi, case..esac one-liners
  ifnot (NULL == sh_re_match_line("\\b(if|case)\\b.*\\b(fi|esac)\\b\\s*#?"))
    return NULL;

  % presumed case/esac conditions: match some text followed by a right
  % parenthesis, but fail to match if there is a left parenthesis
  % somewhere on the line or if the line begins with the 'case'
  % keyword, since if 'case' and its condition is on the same line,
  % then instead the 'case' keyword should be matched in
  % $SH_Indent_Kws_Re
  ifnot (NULL == sh_re_match_line("(^\\s*\\bcase\\b|\\().*(*SKIP)(*F)|\\S(\\))"))
  {
    kw = "case_cond";
    if (sh_is_kw_in_string_or_comment(")") < 0)
      return NULL;
    if (sh_case_cond_is_end_par())
      return NULL;

    return kw;
  }

  kw = sh_re_match_line(SH_Indent_Kws_Re)[-1];
  if (kw == NULL) return NULL;

  if (sh_is_kw_in_string_or_comment(kw) < 0)
    return NULL;

  return strtrim(kw);
}

% Attempt to find indentation column of parent keyword to a current
% matching keyword in e.g. statement blocks if..fi, esac..case, etc. Should
% work in infinitely nested blocks. For continued lines ..\ return the
% position of the first line part.
private define sh_find_col_matching_kw (goto)
{
  variable this_kw, kw, matching_kw, matching_kw_n = 0, kw_n = 0;
  variable fi_n = 0, if_n = 0;

  kw = sh_get_indent_kw();
  push_spot();

  forever
  {
    % continued lines ...\ find position of parent
    if (sh_is_line_continued())
    {
      while (sh_is_line_continued()) go_up_1();
      break;
    }

    % Attempt to find parent-'if' to these keywords
    if (any(kw == ["elif","else","fi"]))
    {
      do
      {
        this_kw = sh_get_indent_kw();
        if (this_kw == "fi") fi_n++;
        if (this_kw == "if") if_n++;

        if (any(kw == ["elif","else"]))
          if (if_n > fi_n) break;
        if (kw == "fi")
          if (if_n == fi_n) break;
      }
      while (up(1));
      break;
    }

    % match case/esac condition, "..)" to parent 'case' keyword, also with
    % nested case/esac blocks.
    if (kw == "case_cond")
    {
      while (up(1))
      {
        this_kw = sh_get_indent_kw();
        if (this_kw == NULL) continue;
        this_kw = strtrim(this_kw);
        if ("esac" == this_kw) kw_n++;
        if ("case" == this_kw) matching_kw_n++;
        if (matching_kw_n > kw_n) break;
      }

      break;
    }

    % otherwise match the other keywords in the SH_Kws_Hash above.
    matching_kw = SH_Kws_Hash[kw];
    do
    {
      if (kw == sh_get_indent_kw()) kw_n++;
      if (matching_kw == sh_get_indent_kw()) matching_kw_n++;
      if (kw_n == matching_kw_n) break;
    }
    while (up(1));
    break;
  }

  bol_skip_white();
  _get_point; % on stack
  ifnot (goto) pop_spot();
}

% Return keyword on current line and preceding keyword along with
% their positions on the line
private define sh_return_this_and_prev_kw ()
{
  variable this_kw = NULL, this_kw_col = 0, prev_kw = NULL, prev_kw_col = 0;

  push_spot();
  this_kw = sh_get_indent_kw();

  ifnot (NULL == this_kw)
  {
    this_kw = strtrim(this_kw);
    bol_skip_white();
    this_kw_col = _get_point;
  }

  while(up(1))
  {
    bol_skip_white();
    prev_kw = sh_get_indent_kw();
    if (NULL == prev_kw) continue;
    prev_kw = strtrim(prev_kw);
    prev_kw_col = _get_point;
    break;
  }

  pop_spot();
  return (this_kw, this_kw_col, prev_kw, prev_kw_col);
}

% The rules-based indentation of lines.
private define sh_indent_line ()
{
  variable col, this_kw, this_kw_col, prev_kw, prev_kw_col;
  variable matching_kw;

  (this_kw, this_kw_col, prev_kw, prev_kw_col) = sh_return_this_and_prev_kw();

  if (sh_is_line_continued()) % continued lines ...\
  {
    col = sh_find_col_matching_kw(0);
    return sh_indent_spaces(col + SH_Indent);
  }

  % End token for "here documents" must have no indentation. There is
  % no naming standard for these, so just try for these two.
  ifnot (NULL == sh_re_match_line("^\\s*(END|EOF)\\s*$"))
    return sh_indent_spaces(0);

  % if "then" is on a line by itself, align it to "if".
  if (this_kw == "then")
    return sh_indent_spaces(prev_kw_col);

  % indent a case condition relative to its case keyword by one level
  if (this_kw == "case_cond")
  {
    col = sh_find_col_matching_kw(0);
    return sh_indent_spaces(col + SH_Indent);
  }

  % Align these keywords to their matching keywords, fi..if, esac..case, etc
  if (any(this_kw == ["fi","else","elif","done","esac","}",")"]))
  {
    col = sh_find_col_matching_kw(0);
    return sh_indent_spaces(col);
  }

  % if "do" keyword is on a line by itself, align to its loop keyword
  if ((this_kw == "do") && (any(prev_kw == ["while","for","repeat","until","select"])))
    return sh_indent_spaces(prev_kw_col);

  % Indent lines following these keywords.
  if (any(prev_kw == ["while","for","if","then","do","case","else","elif","{","(", "case_cond"]))
    return sh_indent_spaces(prev_kw_col + SH_Indent);

  % Align lines under these keywords
  if (any(prev_kw == ["esac","done","fi","}","eval",")"]))
    return sh_indent_spaces(prev_kw_col);

  return sh_indent_spaces(0);
}

% Indent line or a marked region. Usually with <tab>
define sh_indent_region_or_line()
{
  variable reg_endline, i = 1;

  ifnot (is_visible_mark())
    return sh_indent_line();

  trim_buffer();
  check_region(0);
  reg_endline = what_line();
  pop_mark_1();

  do
  {
    flush (sprintf ("indenting buffer ... (%d%%)", (i*100)/reg_endline));
    if (eolp() and bolp()) continue;
    sh_indent_line();
    i++;
  }
  while (down(1) and what_line != reg_endline);
  flush("indent region done");
}

private define _sh_newline_and_indent ()
{
  bskip_white();
  push_spot(); sh_indent_line(); pop_spot();
  insert("\n");
  sh_indent_line();
}

% Insert and expand a statement code block
private define sh_insert_and_expand_construct ()
{
  variable kw = sh_get_indent_kw();
  if ((kw == NULL) ||
      (0 == assoc_key_exists(SH_Indent_Hash, kw) ||
      (not blooking_at(kw))))
    return _sh_newline_and_indent();

  push_visible_mark();
  insert (SH_Indent_Hash[kw]);
  go_right_1();
  exchange_point_and_mark();
  sh_indent_region_or_line();
  () = re_bsearch("@");
  () = replace_match("", 1);
}

% Briefly highlight the matching keyword that begins a code block or
% sub-block if standing on the keyword that ends it. Sometimes helpful
% in long convoluted syntaxes.
define sh_show_matching_kw ()
{
  variable kw = sh_get_indent_kw(), matching_kw;
  if (kw == NULL) return;
  ifnot (assoc_key_exists(SH_Kws_Hash, kw)) return;
  matching_kw = SH_Kws_Hash[kw];
  () = sh_find_col_matching_kw(1); % go to matching kw
  () = ffind("$matching_kw"$);
  push_visible_mark();
  () = right(strlen(matching_kw));
  update(1); sleep(1.5);
  vmessage("matches \"$matching_kw\" in line %d"$, what_line());
  pop_mark_0(); pop_spot();
}

% This happens when you type <enter> after one of $SH_Indent_Kws_Re
define sh_newline_and_indent ()
{
  if (SH_Expand_Kw_Syntax)
    return sh_insert_and_expand_construct();

  _sh_newline_and_indent();
}

private variable Shellcheck_Lines = Int_Type[0];
private variable Shellcheck_Linenos = Int_Type[0];
private variable Shellcheck_Err_Cols = Int_Type[0];

% Reset the shellcheck error index and remove line coloring.
private define sh_shellcheck_reset ()
{
  variable lineno;
  push_spot();
  foreach lineno (Shellcheck_Linenos)
  {
    goto_line(lineno);
    set_line_color(0);
  }
  pop_spot();
  Shellcheck_Lines = Int_Type[0];
  Shellcheck_Linenos = Int_Type[0];
  Shellcheck_Err_Cols = Int_Type[0];
  set_blocal_var(0, "Shellcheck_Indexed");
  call("redraw");
}

% Color and index lines identified by shellcheck as having errors/warnings.
define sh_index_shellcheck_errors ()
{
  variable line, col, lineno, lineno_col, buf, fp, file, dir, cmd;
  variable tmpfile = "/tmp/shellcheck_tmpfile";

  sh_shellcheck_reset();
  push_spot_bob(); push_mark_eob();
  () = write_string_to_file(bufsubstr(), tmpfile);
  pop_spot();
  cmd = "shellcheck --severity=error --severity=warning --format=gcc $tmpfile"$;
  flush("Indexing shellcheck errors/warnings ...");
  fp = popen (cmd, "r");
  Shellcheck_Lines = fgetslines(fp);
  ifnot (length(Shellcheck_Lines))
    return flush("shellcheck reported no errors or warnings");
  () = pclose (fp);
  push_spot();
  foreach line (Shellcheck_Lines)
  {
    lineno_col = pcre_matches("(\\d+):(\\d+)", line);
    lineno = integer(lineno_col[1]);
    col = integer(lineno_col[2]);
    goto_line(lineno);
    set_line_color(SH_Shellcheck_Error_Color);
    Shellcheck_Linenos = [Shellcheck_Linenos, lineno];
    Shellcheck_Err_Cols = [Shellcheck_Err_Cols, col];
  }
  pop_spot();
  call("redraw");
  flush("done");
  set_blocal_var(1, "Shellcheck_Indexed");
}

private variable Shellcheck_Wiki_Entry = "";

% Go to next or previous line with errors relative to the editing
% point identified by shellcheck and show the error message from
% shellcheck in the message area.
define sh_goto_next_or_prev_shellcheck_entry (dir)
{
  variable i, err_col, err_lineno, err_msg, this_line = what_line();

  ifnot (1 == get_blocal_var("Shellcheck_Indexed"))
    sh_index_shellcheck_errors();

  try
  {
    if (dir < 0) % find index position of previous error line
      i = where(this_line > Shellcheck_Linenos)[-1];
    else
      i = where(this_line < Shellcheck_Linenos)[0];

    err_lineno = Shellcheck_Linenos[i];
    err_col = Shellcheck_Err_Cols[i];
    goto_line(err_lineno);
    goto_column(err_col);
    err_msg = Shellcheck_Lines[i];
    err_msg = pcre_matches("^.*?:(.*)", err_msg)[1]; % omit file name
    Shellcheck_Wiki_Entry = pcre_matches("SC\\d+", err_msg)[0];
    call("redraw");
    message(err_msg);
  }
  catch IndexError: message("no shellcheck errors/warnings beyond this line");
}

% Show shellcheck error/warning explanation on the shellcheck wiki.
define sh_show_on_shellcheck_wiki ()
{
  ifnot (strlen(Shellcheck_Wiki_Entry))
    return flush("you must jump to an error line first");

  if (NULL == search_path_for_file (getenv("PATH"), SH_Browser))
    throw RunTimeError, "$SH_Browser was not found"$;

  if (get_line_color == SH_Shellcheck_Error_Color)
    () = run_program("$SH_Browser https://www.shellcheck.net/wiki/$Shellcheck_Wiki_Entry"$);
}

ifnot (keymap_p (Mode)) make_keymap (Mode);
definekey_reserved ("sh_show_on_shellcheck_wiki", "W", Mode);
definekey_reserved ("sh_index_shellcheck_errors", "C", Mode);
definekey ("sh_goto_next_or_prev_shellcheck_entry\(-1\)", Key_Shift_Up, Mode);
definekey ("sh_goto_next_or_prev_shellcheck_entry\(1\)", Key_Shift_Down, Mode);
definekey ("sh_show_matching_kw", Key_Ctrl_PgUp, Mode);

private define sh_menu (menu)
{
  menu_append_item (menu, "Show on Shellcheck Wiki", "sh_show_on_shellcheck_wiki");
  menu_append_item (menu, "Check Buffer With Shellcheck", "sh_index_shellcheck_errors");
  menu_append_item (menu, "Go to Next Shellcheck Error Line", "sh_goto_next_or_prev_shellcheck_entry\(1\)");
  menu_append_item (menu, "Go to Previous Shellcheck Error Line", "sh_goto_next_or_prev_shellcheck_entry\(-1\)");
  menu_append_item (menu, "Show Matching Keyword", "sh_show_matching_kw");
}

define sh_mode ()
{
  define_blocal_var("Shellcheck_Indexed", 0);
  sh_setup_syntax();
  set_comment_info(Mode, "# ", "", 0x01);
  set_mode(Mode, 4);
  use_keymap (Mode);
  set_buffer_hook("indent_hook", "sh_indent_region_or_line");
  set_buffer_hook("newline_indent_hook", "sh_newline_and_indent");
  mode_set_mode_info (Mode, "init_mode_menu", &sh_menu);
  mode_set_mode_info ("SH", "fold_info", "#{{{\r#}}}\r\r");
  run_mode_hooks("sh_mode_hook");
}
