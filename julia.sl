require("pcre");
require("keydefs");
autoload("add_keywords", "syntax");

% The default number of spaces per indentation level
custom_variable ("Julia_Indent_Default", 4);

% This may be a single path or two or more space separated paths where
% julia library files reside
custom_variable ("Julia_Library_Path", "/usr/share/julia");

private variable Version = "0.2.7";
private variable Mode = "julia";
private variable Juliafuncs;
private variable Syntax_Table = Mode;
private variable Hlp_Hash = Assoc_Type[String_Type, ""];

% These are all highlighted
private variable Julia_Reserved_Keywords =
  ["baremodule", "begin", "break", "catch", "const", "continue", "do", "else",
   "elseif", "end", "export", "false", "finally", "for", "function", "global",
   "if", "import", "let", "local", "macro", "module", "quote", "return",
   "struct", "true", "try", "using", "while", "where", "in", "isa", "foreach"];

% Keywords that begin a block
private variable Julia_Block_Beg_Kws =
  ["begin", "catch", "do", "else", "elseif", "finally", "for",
   "function", "if", "let", "macro", "quote", "try", "while","struct",
   "abstract type", "primitive type"];

% Keywords that end a block
private variable Julia_Block_End_Kws =
  ["end", "else", "elseif", "catch", "finally"];

% Keywords where successive lines belonging to them may be indented
% one level
private variable Julia_Open_Block_Kws =
  ["const", "import", "export", "using"];

ifnot (keymap_p(Mode)) make_keymap(Mode);
definekey("julia_help", Key_F1, Mode);
definekey("julia_apropos", Key_F2, Mode);
definekey("exec_julia_code_in_line_or_region", Key_F9, Mode);
definekey_reserved("julia_indent_buffer", "i", Mode);
definekey_reserved("show_version_and_licence_info", "v", Mode);
% definekey_reserved("evalfile\(\"/home/mojo/devel/slang/julia/julia.sl\"\)", "e", Mode);

private define julia_get_word()
{
  define_word (get_blocal_var("julia_chars"));
  push_spot ();
  bskip_word_chars ();
  push_mark ();
  skip_word_chars ();
  bufsubstr ();
  pop_spot ();
}

% Fit window height to text lines
private define julia_fit_window()
{
  variable win_nlines, endline_pos, nlines_diff;

  win_nlines = window_info('r');
  eob(); bskip_white();
  endline_pos = what_line();
  nlines_diff = win_nlines-endline_pos;
  otherwindow();

  loop(nlines_diff)
    enlargewin();

  otherwindow;
}

% Add keywords to a syntax table for highlighting
private define add_kws_to_table(kws, tbl, n)
{
  variable kws_i, i;

  _for i (1, 48, 1) % 48 is the keyword length limit.
  {
    kws_i = kws[where(strlen(kws) == i)];
    kws_i = kws_i[array_sort (kws_i)];
    kws_i = strtrim(kws_i);
    kws_i = strjoin(kws_i, "");

    ifnot (strlen (kws_i)) continue;

    () = add_keywords(Syntax_Table, kws_i, i, n);
  }
}

% Create a hash of julia function names as keys and their help
% descriptions as values. This requires slang version pre2.3.3-59
private define create_hlp_index()
{
  variable st, libdir = "", libdirs = String_Type[0];
  variable entries, cmd, fp, key, val, i, fname = "", descr = "";
  variable match_chars = get_blocal_var("julia_chars");

  if (length(Hlp_Hash)) return;

  foreach libdir (strtok(Julia_Library_Path))
  {
    st = stat_file (libdir);
    if (st == NULL)
    {
      flush("$libdir does not exist"$);
      sleep(1);
    }
    else
      libdirs = [libdirs, libdir];
  }

  ifnot (length(libdirs))
    throw RunTimeError, "$Julia_Library_Path not valid, no help available"$;
  else
    libdirs = strjoin (libdirs, " ");

  flush("creating help index, this may take a couple of seconds ...");

  % The actual extraction of the documentation: This relies on the
  % function descriptions in the julia programming library files
  % begin with '"""' followed by a newline, followed by four spaces of
  % indentation followed by the function name followed by one or more
  % lines of description and ending with '"""'. The vertical tab
  % control character, '^K', is the chosen delimiter for splitting.
  cmd = "find $libdirs -type f -name \"*.jl\" -print0 |"$ +
        "xargs -0 sed -En '/^\"\"\"/{:a;N;/^\\s{4}\[$match_chars\]+"$ +
        "\\S/M!D;/\\n\"\"\"/!ba;p;d}'| sed '/^\"\"\"/{N;s//\"\"\"\\n/}' |" +
        "sed '/^\"\"\"/d'";

  fp = popen (cmd, "r");
  entries = strjoin (fgetslines (fp), "");
  () = pclose(fp);
  entries = strchop(entries, '', 0);

  % split help entries in two catching subpatterns, one the function
  % name and the other its description
  entries = array_map(Array_Type, &pcre_matches, "([$match_chars]+)(.*)"$,
                      entries; options=PCRE_DOTALL);

  _for i (0, length (entries)-1, 1)
  {
    try
    {
      fname = entries[i][1];
      descr = entries[i][2];
      if (assoc_key_exists (Hlp_Hash, fname)) % if item is documented more than once
        descr = Hlp_Hash[fname] + "\n" + descr;
      Hlp_Hash[fname] = descr;
      fname = ""; descr = "";
    }
    catch IndexError;
  }

  Juliafuncs = assoc_get_keys(Hlp_Hash);
  Juliafuncs = Juliafuncs[array_sort(Juliafuncs)];
}

% Get all the column positions of a substring in a line.
private define get_substr_positions(str, substr)
{
  variable pos = 1, offset = 1, pos_arr = Int_Type[0];

  while (pos = string_match (str, substr, offset), pos != 0)
  {
    offset = pos + strlen(substr);
    pos_arr = [pos_arr, pos];
  }

  if (length(pos_arr))
    return pos_arr;
  else
    return Int_Type[0];
}

% Has word these characters on either side?
private define is_within_chars(str, word, beg_ch, end_ch)
{
  variable pos_beg_char = get_substr_positions(str, beg_ch);
  variable pos_end_char = get_substr_positions(str, end_ch);
  variable pos_word = get_substr_positions(str, word);

  if (length(pos_beg_char) and length(pos_end_char))
  {
    pos_beg_char = pos_beg_char[where(pos_beg_char < pos_word[0])];
    pos_end_char = pos_end_char[where(pos_end_char > pos_word[0]+strlen(word)-1)];
    if (length(pos_beg_char) and length(pos_end_char))
      return 1;
  }
  return 0;
}

% Are we inside a triple quote text block?
private define is_inside_triple_quote_block()
{
  variable i = 0;

  push_spot();
  while (bsearch("\"\"\""))
    i++;
  pop_spot();

  if (i mod 2) return 1; % odd number of """ lines above (or below) editing point == inside

  return 0;
}

private define julia_setup_syntax()
{
  variable bg;

  (, bg) = get_color("normal"); % get the current background color
  set_color("keyword", "red", bg);
  set_color("operator", "yellow", bg);
  create_syntax_table(Syntax_Table);
  define_syntax("#", "", '%', Syntax_Table);
  define_syntax("([{", ")]}", '(', Syntax_Table);
  define_syntax('"', '"', Syntax_Table);
  define_syntax('`', '"', Syntax_Table);
  define_syntax('\'', '\'', Syntax_Table);
  define_syntax('\\', '\\', Syntax_Table);
  define_syntax(get_blocal_var("julia_chars"), 'w', Syntax_Table); % words
  % define_syntax("-+0-9a-fA-F.xX", '0', Syntax_Table);            % Numbers
  define_syntax(",;:.", ',', Syntax_Table);
  % define_syntax ('#', '#', Syntax_Table);
  define_syntax("-+/&*=<>|!~^", '+', Syntax_Table);
  use_syntax_table(Syntax_Table);
}

% Attempt to find the correct indentation to the contextual left
% parenthesis or brace of the remainder of a code line after a line
% break. It only tries to find positions on the current line and will
% fail in nested syntaxes with a mix of braces and parenthesises.
private define get_line_break_indent_pos()
{
  variable mypos = what_column();
  variable str;

  if ((eolp()) || (bolp())) return 0;

  push_spot(); str = line_as_string(); pop_spot();

  ifnot ((is_substr(str, "{")) && (is_substr(str, "}")) ||
         (is_substr(str, "(")) && (is_substr(str, ")")))
  {
    return 0;
  }

  variable lb_pos = get_substr_positions(str, "{"); % integer array of column positions
  variable lb_pos_bf_mypos = lb_pos[where (lb_pos < mypos)];

  variable lp_pos = get_substr_positions(str, "(");
  variable lp_pos_bf_mypos = lp_pos[where (lp_pos < mypos)];

  variable rb_pos = get_substr_positions(str, "}");
  variable rb_pos_af_mypos = rb_pos[where (rb_pos > mypos)];

  variable rp_pos = get_substr_positions(str, ")");
  variable rp_pos_af_mypos = rp_pos[where (rp_pos > mypos)];

  if ((length (lp_pos_bf_mypos)) && (length (rp_pos_af_mypos)))
  {
    variable lp_rp_diff_n = length(lp_pos_bf_mypos) - length(rp_pos_af_mypos);

    if (lp_rp_diff_n <= 0)
      return lp_pos_bf_mypos[0];
    if (lp_rp_diff_n == 1)
      return lp_pos_bf_mypos[-1];
    if (lp_rp_diff_n > 1)
      return lp_pos_bf_mypos[length (lp_pos_bf_mypos)-lp_rp_diff_n];
    }

  if ((length (lb_pos_bf_mypos)) && (length (rb_pos_af_mypos)))
  {
    variable lb_rb_diff_n = length(lb_pos_bf_mypos) - length(rb_pos_af_mypos);

    if (lb_rb_diff_n == 0)
      return lp_pos_bf_mypos[0];
    if (lb_rb_diff_n == 1)
      return lp_pos_bf_mypos[-1];
    if (lb_rb_diff_n > 1)
      return lp_pos_bf_mypos[length (lp_pos_bf_mypos)-lp_rp_diff_n];
  }

  return 0;
}

private define break_and_indent_codeline()
{
  variable indentation = get_line_break_indent_pos();
  insert ("\n"); trim; insert_spaces(indentation);
}

private variable All_Block_Kws = String_Type[0];
All_Block_Kws = [All_Block_Kws, Julia_Block_Beg_Kws, Julia_Block_End_Kws, Julia_Open_Block_Kws];
All_Block_Kws = array_map (String_Type, &strcat, "\\b", All_Block_Kws, "\\b"); % whole words
All_Block_Kws = strjoin (All_Block_Kws, "|"); % OR'ed regexp of all keywords

% repeat captured kw substrings. Skip kw if prefixed with any of ".:@[
private variable Pat = "(?<!\"|\\.|:|@|\\[)($All_Block_Kws)(?:.*(?<!\"|\\.|:|@|\\[)($All_Block_Kws))?"$;

% The vetting of what keyword instances should influence the indentation
% It works on a line-by-line basis.
private define julia_get_kw()
{
  variable kws, kw = "", line;

  push_spot (); line = line_as_string(); pop_spot();

  if (is_substr(line, " # "))
    line = strchop(line, '#', 0)[0]; % remove a comment part of a code line

  kws = pcre_matches(Pat, line); % see above for kws and pat
  kws = kws[[1:]]; % 1st match in a pcre array of captured substrings is the whole match
                   % which is discarded here
  if (length (kws))
  {
    kw = kws[0];

    if ((is_inside_triple_quote_block) ||             % omit kws inside triple quote text blocks
        (length (kws) > 1) && (kws[-1] == "end") ||   % one line blocks, "function ... end"
        (is_within_chars(line, kw, "\"", "\"")) ||    % omit kws within double quoted strings
        (is_within_chars(line, kw, "\\[", "\\]"))  || % omit kws within brackets
        (is_within_chars(line, kw, "(", ")")))        % omit kws within parenthesises
      kw = NULL;
  }
  else
    kw = NULL;

  return kw, kws;
}

% Pop up a list of function names to complete from
private define complete_func_name_popup(word)
{
  variable match_funcs, func = "";

  match_funcs = Juliafuncs[where(array_map (Int_Type, &string_match, Juliafuncs, "^$word"$, 1))];

  if (length(match_funcs))
  {
    ungetkey('\t');
    func = read_string_with_completion("?", "", strjoin (match_funcs, ","));
  }

  return func;
}

% Get the next or previous, at most, 15 keywords relative to the
% editing point and add them to a list of lists, containing the
% keyword and its column and line positions. The first word may or may
% not be a keyword, the next preceding words must be keywords.
private define get_kws_cols_linenos(dir)
{
  variable kws_cols = {}, kws, kw, col, lineno;
  variable search_fun = &fsearch(), move = &down();

  EXIT_BLOCK { pop_spot(); }

  if (dir < 0)
  {
    search_fun = &bsearch();
    move = &up();
  }
  push_spot();
  bol_skip_white();
  col = what_column();
  lineno = what_line();
  (kw, kws) = julia_get_kw();

  list_append(kws_cols, {kw, col, lineno});

  ifnot (@move(1))
    return kws_cols;
  do
  {
    if (length(kws_cols) == 15) break;
    bol_skip_white();
    col = what_column();
    lineno = what_line();

    if (looking_at("\"\"\""))
      () = @search_fun("\"\"\""); % skip triple quoted text blocks

    if (looking_at("\"")) continue;
    if (looking_at("#")) continue; % skip comment lines

    (kw, kws) = julia_get_kw();

    if ((length (kws) == 2) && (any(kws[0] == Julia_Block_Beg_Kws))
                            && (any(kws[1] == Julia_Block_Beg_Kws)))
      col += Julia_Indent_Default;

    ifnot (kw == NULL)
      list_append(kws_cols, {kw, col, lineno});
  }
  while (@move(1));

  return kws_cols;
}

% Determine the column position to indent to
private define get_indentation()
{
  variable kws_cols, i = 0;
  variable this_word = "", prev_kw = "", this_word_col = 0, prev_kw_col = 0;
  variable prev_kw_open_block = "";

  kws_cols = get_kws_cols_linenos(-1);

  if (is_inside_triple_quote_block)
  {
    if (looking_at("\"\"\""))
      return 0;
    else
      return Julia_Indent_Default;
  }

  this_word = kws_cols[0][0];
  this_word_col = kws_cols[0][1]-1;

  _for i (1, length(kws_cols)-1, 1)
  {
    if (any(kws_cols[i][0] == Julia_Block_Beg_Kws) or
        any(kws_cols[i][0] == Julia_Block_End_Kws))
    {
      prev_kw = kws_cols[i][0];
      prev_kw_col = kws_cols[i][1]-1;
      break;
    }
    if (any(kws_cols[i][0] == Julia_Open_Block_Kws))
    {
      prev_kw_open_block = kws_cols[i][0];
      prev_kw_col = kws_cols[i][1]-1;
      continue;
    }
  }
  variable indent_after_prev_kw = prev_kw_col + Julia_Indent_Default;
  variable dedent_from_prev_kw = prev_kw_col - Julia_Indent_Default;
  variable align_indent_to_prev_kw = prev_kw_col;

  if ((any(this_word == Julia_Block_Beg_Kws) && (0 == strlen(prev_kw))))
    return 0;
  % align indetation of end block kws to previous kw, unless that
  % being 'end' in which case dedent one level.
  if (any(this_word == Julia_Block_End_Kws))
  {
    if (prev_kw == "end")
      return dedent_from_prev_kw;
    else
      return align_indent_to_prev_kw;
  }

  % otherwise always align to 'end' keyword
  if (any(this_word != "end") and prev_kw == "end")
    return align_indent_to_prev_kw;

  % 'export', 'import' etc. flush left plus one or more lines
  % belonging to them.
  if ((this_word == NULL) && (strlen(prev_kw_open_block)) && (prev_kw_col == 0))
    return Julia_Indent_Default;

  if (any (prev_kw == Julia_Block_Beg_Kws))
    return indent_after_prev_kw;

  return NULL;
}

private define julia_indent_line()
{
  variable indentation = get_indentation();

  if (indentation == NULL) return skip_white();

  bol(); trim(); insert_spaces(indentation);
}

define julia_newline_and_indent()
{
  ifnot (eolp())
  {
    bskip_white();

    if(bolp())
    {
      insert("\n"); julia_indent_line(); go_up_1();
      return julia_indent_line;
    }
    else
      return break_and_indent_codeline();
  }
  julia_indent_line(); eol();
  insert("\n");
  julia_indent_line();
}

define julia_indent_region_or_line()
{
  variable reg_endline, i = 1;

  ifnot (is_visible_mark())
    return julia_indent_line();

  check_region(0);
  reg_endline = what_line();
  pop_mark_1();

  do
  {
    flush (sprintf ("indenting buffer ... (%d%%)", (i*100)/reg_endline));
    if (eolp() and bolp()) continue;
    julia_indent_line();
    i++;
  }
  while (down(1) and what_line != reg_endline);
  flush("indent region done");
}

define julia_indent_buffer()
{
  variable i = 1, nlines;

  push_spot(); eob(); nlines = what_line(); pop_spot();
  push_spot_bob();
  do
  {
    flush (sprintf ("indenting buffer ... (%d%%)", (i*100)/nlines));
    if (eolp() and bolp()) continue;
    julia_indent_line;
    i++;
  }
  while (down_1);
  pop_spot;
  flush("indent buffer done");
}

% Scroll upwards between keyword levels in functions
define scroll_func_levels_backward()
{
  variable kws_lines_cols = get_kws_cols_linenos(-1);
  try
    variable prev_kw_lineno = kws_lines_cols[1][2];
  catch IndexError: return; % we've run out of previous keywords
  goto_line(prev_kw_lineno);
  bol_skip_white();
}

% Scroll downwards between keyword levels in functions
define scroll_func_levels_forward()
{
  variable kws_lines_cols = get_kws_cols_linenos(1);
  try
    variable next_kw_lineno = kws_lines_cols[1][2];
  catch IndexError: return;
  goto_line(next_kw_lineno);
  bol_skip_white();
}

variable hlpwords = String_Type[0];
variable i = 0;

define julia_help();

define cycle_help_history_backward()
{
  if (i <= 0)
    i = length(hlpwords);
  julia_help(hlpwords[i-1]);
  i--;
}

define cycle_help_history_forward()
{
  if (i >= length(hlpwords)-1)
  {
    flush("end of history");
    i = 0;
  }
  julia_help(hlpwords[i+1]);
  i++;
}

variable hlpword;
variable hlpbuf = "*Help*";
variable oldbuf = "";

define show_help(item) % item is String_Type
{
  if (buffer_visible (hlpbuf))
  {
    delbuf(hlpbuf);
    sw2buf(oldbuf);
    onewindow ();
  }
  oldbuf = pop2buf_whatbuf(hlpbuf);
  define_blocal_var ("julia_chars", "-a-zA-Z0-9_\:.|~&@!ℵ∘∞γ≠≢≥÷∀∃⇒εδ∋φℯπ∉⊈⊊<>^=+*/");
  define_word (get_blocal_var("julia_chars"));
  insert(item);
  set_buffer_modified_flag(0);
  julia_fit_window();
  most_mode(); bob();
  use_syntax_table(Mode);
  local_setkey("julia_help", "\r");
  local_setkey("cycle_help_history_backward", Key_Left);
  local_setkey("cycle_help_history_forward", Key_Right);
}

define julia_help()
{
  if (_slang_version < 20303)
    throw RunTimeError, "This requires slang version pre2.3.3-59 or newer";

  ifnot (length (Hlp_Hash))
    throw RunTimeError, "Help index is empty. Check the path in Julia_Library_Path";

  ifnot (_NARGS)
    hlpword = julia_get_word();
  else
    hlpword = ();

  if (strlen(hlpword) > 50)
    return show_help(hlpword);

  hlpword = strtrim_beg(hlpword, "!");

  ifnot (strlen(hlpword))
    hlpword = read_with_completion(strjoin(Juliafuncs, ","), "Function?", "", "", 's');

  ifnot (any(hlpword == Juliafuncs))
  {
    ifnot (length(where (array_map(Int_Type, &string_match, Juliafuncs, "^$hlpword"$, 1))))
      hlpword = read_with_completion(strjoin(Juliafuncs, ","), "Function?", hlpword, "", 's');
    else
      hlpword = complete_func_name_popup(hlpword);
  }

  ifnot (assoc_key_exists(Hlp_Hash, hlpword))
    return flush("no help for \"$hlpword\""$);

  ifnot (buffer_visible(hlpbuf))
  {
    i = 0;
    hlpwords = String_Type[0];
  }

  ifnot (any(hlpword == hlpwords))
  {
    i++;
    hlpwords = [hlpwords, hlpword];
  }

  show_help(hlpword + Hlp_Hash[hlpword]);
}

define julia_apropos()
{
  ifnot (length (Hlp_Hash))
    throw RunTimeError, "Help index is empty. Check the path in Julia_Library_Path";

  variable str, key, val, keys = String_Type[0];
  str = read_mini("Apropos:", "", "");

  % list function names with search string first, then functions w/descriptions
  % that has search string
  foreach key, val (Hlp_Hash)
  {
    if (string_match (key, "\\C$str"$, 1))
      keys = [keys, key];
  }
  foreach key, val (Hlp_Hash)
  {
    if (string_match (val, "\\C$str"$, 1))
    {
      ifnot (any (key == keys))
        keys = [keys, key];
    }
  }

  ifnot (buffer_visible(hlpbuf))
  {
    i = 0;
    hlpwords = String_Type[0];
  }

  keys = strjoin(keys, "\n");
  hlpwords = [hlpwords, keys];
  show_help(keys);
}

% Show output from executing julia code in line or region in a window
define exec_julia_code_in_line_or_region()
{
  variable julia_prg = search_path_for_file (getenv("PATH"), "julia");
  variable outfile = "/tmp/jed_exec_julia.jl";
  variable errorsfile = "/tmp/exec_julia_errors";
  variable str;

  if (NULL == julia_prg)
    throw RunTimeError, "julia is not installed";

  () = delete_file(outfile);
  () = delete_file(errorsfile);

  push_spot();

  ifnot (markp())
    str = line_as_string();
  else
    str = bufsubstr();

  str = strtrim(str);
  () = write_string_to_file(str, outfile);
  pop_spot();

  pop2buf ("***Output from code execution in $outfile***"$);
  () = run_shell_cmd("$julia_prg 2>$errorsfile < $outfile"$);

  if (1 == file_status(errorsfile))
    () = insert_file(errorsfile);

  set_buffer_modified_flag(0);
  julia_fit_window();
  most_mode();
  bob();
}

define show_version_and_licence_info()
{
  variable license =
    ["A julia mode for Jed, version: $Version"$,
     "Copyright (C) 2021-: Morten Bo Johansen <listmail@mbjnet.dk>",
     "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>",
     "This is free software: you are free to change and redistribute it.",
     "There is ABSOLUTELY NO WARRANTY"];

  pop2buf ("***Version and License Information***");
  insert (strjoin (license, "\n"));
  julia_fit_window();
  set_buffer_modified_flag(0);
  most_mode();
  bob();
}

define julia_mode()
{
  define_blocal_var("julia_chars", "-a-zA-Z0-9_\:.|~&@!ℵ∘∞γ≠≢≥÷∀∃⇒εδφℯπ∋∉⊈⊊<>^=+*/");
  define_word(get_blocal_var("julia_chars"));
  use_keymap (Mode);
  julia_setup_syntax();
  add_kws_to_table(Julia_Reserved_Keywords, Syntax_Table, 0);
  create_hlp_index();
  if (length(Juliafuncs) > 1)
    add_kws_to_table(Juliafuncs, Syntax_Table, 1);
  set_comment_info(Mode, "# ", "", 0x01);
  set_mode(Mode, 4);
  set_buffer_hook("newline_indent_hook", "julia_newline_and_indent");
  set_buffer_hook("indent_hook", "julia_indent_region_or_line");
  set_buffer_hook("backward_paragraph_hook", "scroll_func_levels_backward");
  set_buffer_hook("forward_paragraph_hook", "scroll_func_levels_forward");
  run_mode_hooks("julia_mode_hook");
}
