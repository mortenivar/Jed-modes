% sh.sl - a mode for the Jed editor to facilitate the editing of shell scripts.
% Author: Morten Bo Johansen <mortenbo at hotmail dot com>
% License: https://www.gnu.org/licenses/gpl-3.0.en.html
require("pcre");
require("keydefs");
autoload("add_keywords", "syntax");

% User defined variable of how much indentation is wanted.
custom_variable("SH_Indent", 2);

% User defined variable of browser
custom_variable("SH_Browser", "lynx");

% User defined variable of automatic code block insertion
custom_variable("SH_Expand_Kw_Syntax", 1);

% The minimum severity level for shellcheck reporting. Possible values
% are "style", "info", "warning" and "error".
custom_variable("SH_Shellcheck_Severity_Level", "warning");

private variable
  Mode = "SH",
  Version = "0.6.3",
  SH_Indent_Kws,
  SH_Indent_Kws_Re,
  SH_Shellcheck_Error_Color = color_number("preprocess"),
  SH_Kws_Hash = Assoc_Type[String_Type, ""],
  SH_Indent_Hash = Assoc_Type[String_Type, ""];

% Keywords that trigger some indentation rule
SH_Indent_Kws = ["if","fi","else","elif","esac","done","then","for",
                 "while","until","select","eval"];

% OR'ed expression of $SH_Indent_Kws
SH_Indent_Kws_Re = strjoin(SH_Indent_Kws, "|");

% Regular expression for keywords with some added indentation triggers
% such as parentheses and braces. If 'do' is on the same line as loop
% keyword, 'do' should always be matched. If a left parenthesis is at
% the end of the line, it should always be matched. Also allow for
% trailing comments in both cases.
SH_Indent_Kws_Re = strcat("^\\h*\\b($SH_Indent_Kws_Re)\\b\\h*(?:.*?(\\bdo\\b|{)?)\\h*(?:[^$\\{]#.*?)?$"$,
                          % "do" if not preceded by one of $SH_Indent_Kws followed by "eval" or "test"
                          "|\\b(do)\\b\\h*(?:\\beval\\b|\\btest\\b|#)",
                          % "do" alone possibly followed by a comment
                          "|^\\h*\\bdo\\b\\h*(?:#.*?)?$",
                          % case
                          "|\\b(case)\\b(?:.*?\\bin\\b.*?)?\\)?$",
                          % right parenthesis at begin of line
                          "|^\\h*(\\))\\h*",
                          % right/left curly braces at end of line
                          "|({|})'?\\h*(?:#.*?)?$",
                          % left /parenthesis or function definition, allow for trailing comment
                          "|(\\(|\\(\\))\\h*(?:#.*?)?$");

% Associative array that will be used to position its paired keywords
% to each other.
SH_Kws_Hash["case_pat"] = "case";
SH_Kws_Hash["esac"] = "case";
SH_Kws_Hash["done"] = "do";
SH_Kws_Hash[")"] = "(";
SH_Kws_Hash["}"] = "{";
SH_Kws_Hash["}{"] = "{";
SH_Kws_Hash["fi"] = "if";
SH_Kws_Hash["else"] = "if";
SH_Kws_Hash["elif"] = "if";

% Associative array to insert and expand syntaxes for its keys
SH_Indent_Hash["if"] = " @; then\n\nfi";
SH_Indent_Hash["elif"] = " @; then\n\n";
SH_Indent_Hash["for"] = " @ in ; do\n\ndone";
SH_Indent_Hash["select"] = " @ in ; do\n\ndone";
SH_Indent_Hash["while"] = " @; do\n\ndone";
SH_Indent_Hash["until"] = " @; do\n\ndone";
SH_Indent_Hash["case"] = " $@ in\n*)\n;;\n*)\n;;\nesac";

% For highlighting
private variable SH_Kws = [SH_Indent_Kws, ["do","!","in",";;","time","case","END","EOF"]];

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
   zprof,zpty,zregexparse,zsocket,zstyle,ztcp,coproc,compgen,complete,compopt,
   function,allexport,braceexpand,emacs,errexit,errtrace,functrace,hashall,histexpand,
   keyword,monitor,noexec,nounset,onecmd,physical,pipefail,posix,privileged,
   verbose,xtrace,autocd,cdspell,checkhash,checkjobs,checkwinsize,cmdhist,compat31,
   compat32,compat40,compat41,dirspell,dotglob,execfail,expand_aliases,extdebug,
   extglob,extquote,failglob,force_fignore,globstar,gnu_errfmt,histappend,histreedit,
   histverify,hostcomplete,huponexit,interactive_comments,lastpipe,lithist,login_shell,
   mailwarn,no_empty_cmd_completion,nocaseglob,nocasematch,nullglob,progcomp,promptvars,
   restricted_shell,shift_verbose,sourcepath,xpg_echo,alloc,dosh,hist,map,repeat,savehistory`;

SH_Builtins = strtrim(strchop(SH_Builtins, ',', 0));

% For highlighting.
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
   STTY,TIMEFMT,TMOUT,TMPPREFIX,varcmds,watch,WATCH,WATCHFMT,WORDCHARS,ZDOTDIR,
   BASHPID,BASH_ALIASES,BASH_ARGC,BASH_ARGV,BASH_CMDS,BASH_COMMAND,
   BASH_EXECUTION_STRING,BASH_LINENO,BASHOPTS,BASH_REMATCH,BASH_SOURCE,
   BASH_SUBSHELL,BASH_XTRACEFD,CDPATH,COLUMNS,COMP_KEY,COMP_TYPE,
   COMP_WORDBREAKS,EMACS,FUNCNEST,HISTTIMEFORMAT,HOME,HOSTNAME,
   LANG,LC_ALL,LC_COLLATE,LC_CTYPE,LC_MESSAGES,LC_NUMERIC,LINES,
   MAIL,MAILCHECK,MAILPATH,OPTARG,OPTIND,PATH,PROMPT_DIRTRIM,PS1,PS2,
   SHELL,TMPDIR,SIGABRT,SIGALRM,SIGBUS,SIGCHLD,SIGCONT,SIGFPE,SIGHUP,
   SIGILL,SIGINT,SIGIO,SIGKILL,SIGPIPE,SIGPROF,SIGPWR,SIGQUIT,SIGRTMAX,
   SIGRTMIN,SIGSEGV,SIGSTKFLT,SIGSTOP,SIGSYS,SIGTERM,SIGTRAP,SIGTSTP,
   SIGTTIN,SIGTTOU,SIGURG,SIGUSR1,SIGUSR2,SIGVTALRM,SIGWINCH,SIGXCPU,SIGXFSZ`;

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

% The following two, now slightly modified syntax schemes were
% pilfered from shmode.sl that ships with Jed:

% Unfortunately, the editor cannot currently correctly deal with multiple 
% string characters.  So, inorder to handle something like:
%    echo "I'd rather be home"
% make the '"' character the actual string character but also give '\'' 
% a string syntax.  However, this will cause '"' to give problems but 
% usually, '"' characters will be paired.
define_syntax ('\'', '"', Mode);
define_syntax ('"', '"', Mode);
define_syntax ('\\', '\\', Mode);
define_syntax ("-0-9a-zA-Z_", 'w', Mode);        % words
define_syntax ("-+0-9", '0', Mode);   % Numbers
define_syntax (",;:", ',', Mode);
define_syntax ("%-+/&*=<>|!~^", '+', Mode);
define_syntax ("#", "",'%',  Mode);

#ifdef HAS_DFA_SYNTAX
%%DFA_CACHE_BEGIN %%%
private define setup_dfa_callback (Mode)
{
  dfa_define_highlight_rule ("[\\][a-zA-Z]"R, "number", Mode); % backslash escape sequences \a, \E, etc.
  dfa_define_highlight_rule ("[&\|]"R, "operator", Mode);
  dfa_define_highlight_rule ("\\\\\[a-z]", "comment", Mode);
  dfa_define_highlight_rule ("#[^\{\\$].*", "comment", Mode);
  dfa_define_highlight_rule ("[0-9]+", "number", Mode);
  dfa_define_highlight_rule ("\"([^\\\\\"]|\\\\.)*\"", "string", Mode);
  dfa_define_highlight_rule ("\"([^\\\\\"]|\\\\.)*$", "string", Mode);
  dfa_define_highlight_rule ("'[^']*'", "string", Mode);
  dfa_define_highlight_rule ("'[^']*$", "string", Mode);
  dfa_define_highlight_rule ("[\\|&;\\(\\)<>]", "Qdelimiter", Mode);
  dfa_define_highlight_rule ("[\\[\\]\\*\\?]", "Qoperator", Mode);
  dfa_define_highlight_rule ("[^ \t\"'\\\\\\|&;\\(\\)<>\\[\\]\\*\\?]+", "Knormal", Mode);
  dfa_define_highlight_rule (".", "normal", Mode);
  dfa_build_highlight_table (Mode);
}
dfa_set_init_callback (&setup_dfa_callback, Mode);
%%DFA_CACHE_END %%%
#endif

private define sh_line_as_str()
{
  push_spot_bol(); push_mark_eol(); bufsubstr(); pop_spot();
}

% Matches a pcre style regex pattern in current line.
private define sh_re_match_line(re)
{
  if (NULL == pcre_matches(re, sh_line_as_str())) return NULL;
  return 1;
}

private define sh_is_line_continued()
{
  try
  {
    push_spot ();
    if (up(1))
      if (sh_re_match_line("\\\\$")) return 1;

    return 0;
  }
  finally pop_spot();
}

private define sh_indent_spaces(n)
{
  bol_trim(); insert_spaces(n);
}

% Check if any number of occurrences of one character in a _line_ is not
% balanced by a similar number of another character, e.g. '{' and '}'.
private define sh_is_char_unbalanced(ch1, ch2)
{
  variable ch1_n = count_char_occurrences(sh_line_as_str(), ch1);
  variable ch2_n = count_char_occurrences(sh_line_as_str(), ch2);

  % if (ch1_n == 0 && ch2_n == 0) return 0;

  if (ch1_n > 0)
    if ((ch1_n - ch2_n) mod 2 || ch2_n == 0) return 1; % ch1
  if (ch2_n > 0)
    if ((ch2_n - ch1_n) mod 2 || ch1_n == 0) return 2; % ch2

  return 0;
}

% Count number of characters in a line. Designed for the counting of
% braces. If brace is escaped with '\' don't include in count.
private define sh_count_braces(ch)
{
  variable pos = 0, n = 0, re = "(?<!\\\\)$ch"$;
  variable p = pcre_compile(re);
  variable str = sh_line_as_str();
  
  while (pcre_exec(p, str, pos))
  {
    pos = pcre_nth_match(p, 0)[1];
    n++;
  }
  return n;
}

% Detect a case/esac pattern
private define sh_is_case_pat()
{
  push_spot();

  if (up(1))
  {
    while ((sh_re_match_line("^\\h*#")) || (sh_re_match_line("^\\h*$"))) go_up_1();
    ((sh_re_match_line(";;")) || (sh_re_match_line("case")));
  }

  pop_spot();
}

private variable Sh_Heredoc_Beg_Token = NULL;

% Return the keyword on the current line
private define sh_get_indent_kw()
{
  if (sh_re_match_line("^\\h*$")) return NULL;
  if (sh_re_match_line("^\\h*#")) return NULL;
  
  % The regexp to extract 'heredoc' identifier words. It covers all the
  % odd cases in the scripts I have on my computer.
  variable heredoc_re = "^\\h*(cat|printf)?.*?[^<]<<(?!<)\\h*[-]?[\'\"\\\\]?([_A-Za-z!]+)[\'\"]?(?:.*?)?$";
  
  % case/esac patterns
  if (2 == sh_is_char_unbalanced('(',')')) % ')' not balanced by '('
    if (sh_is_case_pat()) return "case_pat";

  if (sh_re_match_line(heredoc_re))
    Sh_Heredoc_Beg_Token = pcre_matches(heredoc_re, sh_line_as_str())[-1];

  if (sh_re_match_line("^\\h*$Sh_Heredoc_Beg_Token\\h*$"$)) % end of 'heredoc'
    return "heredoc_end_token";

  % These are not very common, but occasionally there are lines where
  % curly braces are used to delimit statment blocks and where the
  % right brace ending the previous block and the left brace beginning
  % the following block are on the same line as e.g. in "} else if {"
  % so create a special "keyword" for that.
  if (sh_re_match_line("^\\h*}.*{\\h*$")) return "}{";

  ifnot (sh_re_match_line(SH_Indent_Kws_Re)) return NULL;

  % one line do..done blocks
  if (sh_re_match_line("\\bdo\\b.*done\\h*#?")) return NULL;

  % if..fi, case..esac one-liners
  if (sh_re_match_line("\\bcase\\b.*\\bin\\b.*\\besac\\b")) return NULL;
  if (sh_re_match_line("\\bif\\b.*\\bfi\\b")) return NULL;

  variable kw = pcre_matches(SH_Indent_Kws_Re, sh_line_as_str())[-1];

  if ((kw == "{") || (kw == "}"))
    ifnot (sh_is_char_unbalanced('{', '}')) return NULL;

  if ((kw == "(") || (kw == ")"))
    ifnot (sh_is_char_unbalanced('(', ')')) return NULL;

  return strtrim(kw);
}

% Return the previous keyword, that is not one of those to be skipped,
% before the current line and its column
private define sh_get_prev_kw_and_col()
{
  try
  {
    push_spot();
    do
      ifnot (up(1)) return (NULL, 0);
    while ((sh_get_indent_kw == NULL) ||
           (sh_get_indent_kw == "heredoc_end_token") ||
           (sh_get_indent_kw == "eval")); % skip these
             
    sh_get_indent_kw(); % previous kw on stack
    bol_skip_white();
    _get_point(); % previous kw col on stack
  }
  finally pop_spot();
}

% Attempt to find indentation column of parent keyword to a current
% matching keyword in e.g. statement blocks if..fi, esac..case, etc. Should
% work in infinitely nested blocks. For continued lines ..\ return the
% position of the first line part.
private define sh_find_col_matching_kw(goto)
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

    if ((kw == NULL) || (not assoc_key_exists(SH_Kws_Hash, kw)))
    {
      pop_spot();
      return 0;
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
        {
          if (if_n == fi_n) break;
        }
      }
      while (up(1));
      break;
    }

    % match case/esac pattern, "..)" to parent 'case' keyword, also with
    % nested case/esac blocks.
    if (kw == "case_pat")
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

    % The parsing of curly braces
    if ((kw == "}") || (kw == "}{"))
    {
      if (kw == "}{") matching_kw_n--;

      do
      {
        if (kw == "}" && sh_get_indent_kw == "}{")
        {
          if (kw_n - matching_kw_n == 1) break;
        }

        kw_n += sh_count_braces("}");
        matching_kw_n += sh_count_braces("{");
        if (kw_n == matching_kw_n) break;
      }
      while (up(1));
      break;
    }

    if (sh_get_indent_kw == ")")
    {
      do
      {
        kw_n += count_char_occurrences(sh_line_as_str, ')');
        matching_kw_n += count_char_occurrences(sh_line_as_str, '(');
        if (kw_n == matching_kw_n) break;
      }
      while (up(1));
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

variable Indent = -1;

% The rules-based indentation of lines. The order in which these rules
% appear matters to some extent.
private define sh_indent_line()
{
  variable sh_this_kw = NULL, sh_prev_kw = NULL, sh_prev_kw_col = 0, col = 0;

  if (sh_is_line_continued()) % continued lines ...\
  {
    col = sh_find_col_matching_kw(0);
    Indent = col + SH_Indent;
    return sh_indent_spaces(Indent);
  }

  sh_this_kw = sh_get_indent_kw();

  % If a line where keyword detection returns NULL follows another
  % similar line, stop backtracking and indent to column of previous line.
  if (Indent >= 0)
  {
    if (sh_this_kw == NULL)
    {
      if (up(1))
      {
        if (NULL == sh_get_indent_kw())
        {
          go_down_1();
          return sh_indent_spaces(Indent);
        }
      }
      go_down_1();
    }
  }
  
  % bactracks to find previous keyword that is not NULL and its column
  (sh_prev_kw, sh_prev_kw_col) = sh_get_prev_kw_and_col();

  % Align a 'do' keyword on a line by itself to its loop keywords
  if ((sh_this_kw == "do") && (any(sh_prev_kw == ["for","while","until","select"])))
  {
    Indent = sh_prev_kw_col;
    return sh_indent_spaces(Indent);
  }
  
  % indent a case pattern relative to its case keyword by one level
  if (sh_this_kw == "case_pat")
  {
    col = sh_find_col_matching_kw(0);
    Indent = col + SH_Indent;
    return sh_indent_spaces(Indent);
  }

  % Align these keywords to their matching keywords, fi..if, esac..case, etc
  if (any(sh_this_kw == ["fi","else","elif","done","esac","}",")","}{"]))
  {
    col = sh_find_col_matching_kw(0);
    Indent = col;
    return sh_indent_spaces(Indent);
  }

  % Align the identifier word for the end of a 'heredoc' string flush left
  if (sh_this_kw == "heredoc_end_token")
  {
    Indent = 0;
    return sh_indent_spaces(Indent);
  }
  
  % 'then' on a line by itself aligned to 'if' or 'elif'
  if ((sh_this_kw == "then") && any(sh_prev_kw == ["if","elif"]))
  {
    Indent = sh_prev_kw_col;
    return sh_indent_spaces(Indent);
  }

  variable indent_after_kws = ["if","for","while","then","do","case","else","elif","{","(", "case_pat","}{"];

  % Indent lines following these keywords
  if (any(sh_prev_kw == indent_after_kws))
  {
    Indent = sh_prev_kw_col + SH_Indent;
    return sh_indent_spaces(Indent);
  }
  
  % function definitions aligned flush left unless after those keywords
  if (sh_this_kw == "()" && not any(sh_prev_kw == indent_after_kws))
  {
    Indent = 0;
    return sh_indent_spaces(Indent);
  }
  
  % Align lines under these keywords
  if (any(sh_prev_kw == ["esac","done","fi","}","eval",")","()"]))
  {
    Indent = sh_prev_kw_col;
    return sh_indent_spaces(Indent);
  }
  
  if (sh_this_kw == NULL)
  {
    Indent = sh_prev_kw_col;
    return sh_indent_spaces(Indent);
  }
}

% Indent line or a marked region. Usually with <tab>
define sh_indent_region_or_line()
{
  variable reg_endline, i = 1;

  ifnot (is_visible_mark())
    return sh_indent_line();

  check_region(0);
  reg_endline = what_line();
  pop_mark_1();

  do
  {
    flush (sprintf ("indenting region ... (%d%%)", (i*100)/reg_endline));
    sh_indent_line();
    i++;
  }
  while (down(1) and what_line != reg_endline);
  flush("indent region done");
}

private define _sh_newline_and_indent()
{
  bskip_white();
  push_spot(); sh_indent_line(); pop_spot();
  insert("\n");
  sh_indent_line();
}

% Insert and expand a statement code block
private define sh_insert_and_expand_construct()
{
  variable kw = sh_get_indent_kw();
  if ((kw == NULL) ||
      (0 == assoc_key_exists(SH_Indent_Hash, kw) ||
      (not blooking_at(kw))))
    return _sh_newline_and_indent();

  push_visible_mark();
  insert (SH_Indent_Hash[kw]);
  if (eobp()) insert("\n");
  go_right_1();
  exchange_point_and_mark();
  sh_indent_region_or_line();
  () = re_bsearch("@");
  () = replace_match("", 1);
}

% Briefly highlight the matching keyword that begins a code block or
% sub-block if standing on the keyword that ends it. Sometimes helpful
% in long convoluted syntaxes.
define sh_show_matching_kw()
{
  variable kw = sh_get_indent_kw(), matching_kw, n = 0;
  if (kw == NULL) return;
  ifnot (assoc_key_exists(SH_Kws_Hash, kw)) return;
  matching_kw = SH_Kws_Hash[kw];
  () = sh_find_col_matching_kw(1); % go to matching kw
  if (matching_kw == "{" || matching_kw == "do")
  {
    eol();
    () = bfind(matching_kw);
  }
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

private variable SH_Shellcheck_Lines = Int_Type[0];
private variable SH_Shellcheck_Linenos = Int_Type[0];
private variable SH_Shellcheck_Err_Cols = Int_Type[0];

% Reset the shellcheck error index and remove line coloring.
private define sh_shellcheck_reset()
{
  push_spot_bob();
  do
    if (get_line_color == SH_Shellcheck_Error_Color)
      set_line_color(0);
  while (down(1));
  pop_spot();
  SH_Shellcheck_Lines = Int_Type[0];
  SH_Shellcheck_Linenos = Int_Type[0];
  SH_Shellcheck_Err_Cols = Int_Type[0];
  set_blocal_var(0, "SH_Shellcheck_Indexed");
  call("redraw");
}

% Color and index lines identified by shellcheck as having errors/warnings.
define sh_index_shellcheck_errors()
{
  variable shellcheck = search_path_for_file (getenv("PATH"), "shellcheck");
  variable line, col, lineno, lineno_col, fp, cmd;
  variable tmpfile = make_tmp_file("/tmp/shellcheck_tmpfile");

  if (shellcheck == NULL)
    throw RunTimeError, "shellcheck program not found";

  sh_shellcheck_reset();
  push_spot_bob(); push_mark_eob();
  () = write_string_to_file(bufsubstr(), tmpfile);
  pop_spot();
  cmd = "$shellcheck --severity=$SH_Shellcheck_Severity_Level --format=gcc $tmpfile"$;
  flush("Indexing shellcheck errors/warnings ...");
  fp = popen (cmd, "r");
  SH_Shellcheck_Lines = fgetslines(fp);
  () = pclose (fp);
  () = delete_file(tmpfile);

  ifnot (length(SH_Shellcheck_Lines))
    return flush("shellcheck reported no errors or warnings");

  push_spot();

  foreach line (SH_Shellcheck_Lines)
  {
    lineno_col = pcre_matches(":(\\d+):(\\d+)", line);
    lineno = integer(lineno_col[1]);
    col = integer(lineno_col[2]);
    goto_line(lineno);
    set_line_color(SH_Shellcheck_Error_Color);
    SH_Shellcheck_Linenos = [SH_Shellcheck_Linenos, lineno];
    SH_Shellcheck_Err_Cols = [SH_Shellcheck_Err_Cols, col];
  }
  pop_spot();
  call("redraw");
  vmessage("found %d lines with issues", length(SH_Shellcheck_Lines));
  set_blocal_var(1, "SH_Shellcheck_Indexed");
}

private variable SH_Shellcheck_Wiki_Entry = "";

% Go to next or previous line with errors relative to the editing
% point identified by shellcheck and show the error message from
% shellcheck in the message area.
define sh_goto_next_or_prev_shellcheck_entry(dir)
{
  variable i, err_col, err_lineno, err_msg, this_line = what_line();

  ifnot (1 == get_blocal_var("SH_Shellcheck_Indexed"))
    sh_index_shellcheck_errors();

  try
  {
    if (dir < 0) % find index position of previous error line
      i = where(this_line > SH_Shellcheck_Linenos)[-1];
    else
      i = where(this_line < SH_Shellcheck_Linenos)[0];

    err_lineno = SH_Shellcheck_Linenos[i];
    err_col = SH_Shellcheck_Err_Cols[i];
    goto_line(err_lineno);
    goto_column(err_col);
    err_msg = SH_Shellcheck_Lines[i];
    err_msg = pcre_matches("^.*?:(.*)", err_msg)[1]; % omit file name
    SH_Shellcheck_Wiki_Entry = pcre_matches("SC\\d+", err_msg)[0];
    call("redraw");
    flush(err_msg);
  }
  catch IndexError: flush("no shellcheck errors/warnings beyond this line");
}

% Show shellcheck error/warning explanation on the shellcheck wiki.
define sh_show_on_shellcheck_wiki()
{
  ifnot (strlen(SH_Shellcheck_Wiki_Entry))
    return flush("you must jump to an error line first");

  if (NULL == search_path_for_file (getenv("PATH"), SH_Browser))
    throw RunTimeError, "$SH_Browser was not found"$;

  if (get_line_color == SH_Shellcheck_Error_Color)
    () = run_program("$SH_Browser https://www.shellcheck.net/wiki/$SH_Shellcheck_Wiki_Entry"$);
}

% Execute the code in a marked region or the entire buffer if no region
% is marked. This ensures that the code is executed in the shell which
% is specified the shebang directive. The output from the execution
% is shown in another window if more than one line. If the output is
% only one line, it is diplayed in the message area.
% NOTE: It only works for non-interactive scripts.
define sh_exec_region_or_buffer()
{
  variable lines, cmd, str, output, fp, shell;
  % extract the shell name from the shebang directive
  variable shell_re = "^#!\\h*/[a-z]+(?:env)?.*?([a-z]+)(?:\\h-e)?$";
  variable tmpfile = make_tmp_file("/tmp/shmode");
  variable outfile = make_tmp_file("/tmp/shmode_out");
  variable env_prg = search_path_for_file (getenv("PATH"), "env");
  
  push_spot_bob();
  shell = pcre_matches(shell_re, sh_line_as_str())[-1];
  pop_spot();

  if (shell == NULL) shell = "sh";

  try
  {
    push_spot();
    ifnot (markp()) mark_buffer ();
    str = bufsubstr();
    pop_spot();
    () = write_string_to_file(str, tmpfile);
    cmd = "$env_prg $shell $tmpfile >$outfile 2>&1"$;
    () = system(cmd);
    fp = fopen(outfile, "r");
    if (fp == NULL) throw ReadError, "could not read $outfile"$;
    lines = fgetslines(fp);
    () = fclose(fp);
    output = strtrim(strjoin(lines, ""));
  }
  finally
  {
    () = remove(outfile);
    () = remove(tmpfile);
  }
  
  if (length(lines) > 1)
  {
    pop2buf("***Output From ${cmd}***"$);
    insert(output);
    bob();
    most_mode();
    flush("type 'q' to close this window");
  }
  else flush(output);
}

define sh_electric_right_brace()
{
  insert("}");
  if (sh_re_match_line("^\\h*}\\h*$"))
    _sh_newline_and_indent();
}

% When typing a left curly brace immediately after a function definition
% move it to the next line and put editing point in an indented position
% after curly brace
define sh_electric_left_brace()
{
  if (blooking_at("()")) % function definition
  {
    insert("\n{");
    _sh_newline_and_indent();
  }
  else insert("{");
}

ifnot (keymap_p (Mode)) make_keymap(Mode);
definekey_reserved ("sh_show_on_shellcheck_wiki", "W", Mode);
definekey_reserved ("sh_index_shellcheck_errors", "C", Mode);
definekey_reserved ("sh_exec_region_or_buffer", "E", Mode);
definekey ("sh_goto_next_or_prev_shellcheck_entry\(-1\)", Key_Shift_Up, Mode);
definekey ("sh_goto_next_or_prev_shellcheck_entry\(1\)", Key_Shift_Down, Mode);
definekey ("sh_show_matching_kw", Key_Ctrl_PgUp, Mode);
definekey ("sh_electric_right_brace", "}", Mode);
definekey ("sh_electric_left_brace", "{", Mode);

private define sh_menu(menu)
{
  menu_append_item (menu, "Check Buffer With Shellcheck", "sh_index_shellcheck_errors");
  menu_append_item (menu, "Go to Next Shellcheck Error Line", "sh_goto_next_or_prev_shellcheck_entry\(1\)");
  menu_append_item (menu, "Go to Previous Shellcheck Error Line", "sh_goto_next_or_prev_shellcheck_entry\(-1\)");
  menu_append_item (menu, "Show on Shellcheck Wiki", "sh_show_on_shellcheck_wiki");
  menu_append_item (menu, "Show Matching Keyword", "sh_show_matching_kw");
  menu_append_item (menu, "Execute Code in Region or Buffer", "sh_exec_region_or_buffer");
}

define sh_mode()
{
  define_blocal_var("SH_Shellcheck_Indexed", 0);
  use_syntax_table(Mode);
  sh_add_kws_to_table(SH_Kws, Mode, 0);
  sh_add_kws_to_table(SH_Builtins, Mode, 1);
  sh_add_kws_to_table(SH_Variables, Mode, 1);
  set_comment_info(Mode, "# ", "", 0x01);
  set_mode(Mode, 4);
  use_keymap (Mode);
  set_buffer_hook("indent_hook", "sh_indent_region_or_line");
  set_buffer_hook("newline_indent_hook", "sh_newline_and_indent");
  mode_set_mode_info (Mode, "init_mode_menu", &sh_menu);
  mode_set_mode_info ("SH", "fold_info", "#{{{\r#}}}\r\r");
  run_mode_hooks("sh_mode_hook");
}
