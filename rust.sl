% rust.sl, a Jed major mode to facilitate the editing of Rust code
% Author: Morten Bo Johansen, mortenbo at hotmail dot com
% License: GPLv3
% Version 0.1.0.1 (2025/03/09)
require("pcre");
require("keydefs");
require("process");
autoload("add_keywords", "syntax");
autoload("c_insert_ket", "cmode");
autoload("c_insert_bra", "cmode");

% The default number of spaces per indentation level
custom_variable("Rust_Indent", 4);

% Additional options to the rustc compiler. It should be a space
% separated list of options, e.g. "-g -O".
custom_variable("Rustc_Opts", "");

private variable Mode = "Rust";
private variable Syntax_Table = Mode;

private variable Rust_Loop_Cond_Keywords = ["if","else","for","while","loop",
                                            "break","continue"];
private variable Rust_Reserved_Keywords =
  ["as","const","crate","enum","extern","false","fn","impl","in","let","match",
   "mod","move","mut","pub","ref","return","self","Self","static","struct",
   "super","trait","true","type","unsafe","use","where","async","await","dyn",
   "abstract","become","box","do","final","macro","override","priv","typeof",
   "unsized","virtual","yield","try","gen","macro_rules","union","safe","raw",
   "dyn"];

% Delimiters that begin a block.
private variable Rust_Block_Beg_Delims = ["{","(","}{","){","[","if"];

% Delimiters that end a block.
private variable Rust_Block_End_Delims = ["}",")","}{","){","]"];

private variable Pat = "(?:.*\\b(if)\\b)|(?:.*([}{\)\(\\[\\]]))";

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

% From C mode. Single quote syntax removed as it collides with the
% single quote character used in Rust's 'lifetime' annotation.
create_syntax_table(Syntax_Table);
define_syntax ("/*", "*/", '%', Syntax_Table);
define_syntax ("//", "", '%', Syntax_Table);
define_syntax ("([{", ")]}", '(', Syntax_Table);
define_syntax ('"', '"', Syntax_Table);
define_syntax ('\\', '\\', Syntax_Table);
define_syntax ("0-9a-zA-Z_", 'w', Syntax_Table);        % words
define_syntax ("-+0-9a-fA-F.xXL", '0', Syntax_Table);   % Numbers
define_syntax (",;.?:", ',', Syntax_Table);
define_syntax ('#', '#', Syntax_Table);
define_syntax ("%-+/&*=<>|!~^", '+', Syntax_Table);
set_syntax_flags (Syntax_Table, 0x4|0x40);

private define rust_line_as_str()
{
  push_spot_bol(); push_mark_eol(); bufsubstr(); pop_spot();
}

% Checks if a pcre style regex pattern matches in the current line.
private define rust_re_match_line(re)
{
  pcre_exec(pcre_compile(re), rust_line_as_str());
}

% A regular expression version of ffind(). It checks if the match
% being in a string or comment and if so, then tries to see if there
% are subsequent matches on the line that might not be.
private define rust_re_ffind(re)
{
  variable pos = 0, p = pcre_compile(re);
  variable str = rust_line_as_str();

  while (pcre_exec(p, str, pos))
  {
    pos = pcre_nth_match(p, 0)[0];
    goto_column(pos + 1);
    pos += 1;
    if (0 == parse_to_point()) break;
  }
}

% If number of left and right delimiters in a line is uneven, return
% the auxiliary unbalanced delimiter.
private define rust_get_unbalanced_delim(ldelim, rdelim)
{
  variable ldelim_n = 0, rdelim_n = 0, line = rust_line_as_str();
  line = str_uncomment_string(line,"\"", "\"");
  ldelim_n = count_char_occurrences(line, ldelim);
  rdelim_n = count_char_occurrences(line, rdelim);

  if (ldelim_n > rdelim_n)
    return char(ldelim);
  if (rdelim_n > ldelim_n)
    return char(rdelim);

  return NULL;
}

% Capture a rust delimiter in a line. Also create some "dummy"
% delimiters, "}{" and "){", to act as dual indentation triggers.
private define rust_get_delim()
{
  variable delims, delim = NULL, ldelim_n, rdelim_n;
  variable line = rust_line_as_str();

  % remove a trailing comment part in a line
  if (rust_re_match_line("^.+\\h*//"))
    line = pcre_matches("(^.*)\\h*//.*?$", line)[-1];

  delims = pcre_matches(Pat, line);
  delims = delims[[1:]];
  delims = delims[wherenot(_isnull(delims))];

  ifnot (length(delims)) return NULL;

  delim = delims[-1];

  if (rust_re_match_line("^\\h*}.*?{\\h*$"))
    delim = "}{";

  if (rust_re_match_line("^\\h*}\\h*\\belse\\b"))
    delim = "}{";

  if (rust_re_match_line("^\\h*\\).*?{\\h*$"))
    delim = "){";

  if (any(delim == ["{","}"]))
    delim = rust_get_unbalanced_delim('{','}');

  if (any(delim == ["(",")"]))
    delim = rust_get_unbalanced_delim('(',')');

  if (any(delim == ["[","]"]))
    delim = rust_get_unbalanced_delim('[',']');

  push_spot();

  if (delim != NULL)
    rust_re_ffind(str_quote_string(delim, "[]()", '\\'));

  if (0 != parse_to_point())
    delim = NULL;

  pop_spot();
  return delim;
}

% Return the position of a line with a matching delimiter. It uses
% Jed's find_matching_delimiter() function to match braces,
% parantheses or brackets. It tries for every delimiter on the line
% until there is a match and then checks if the matching delimiter is
% in a previous line.
private define rust_find_col_matching_delim(delim)
{
  variable lineno = what_line(), pos = 0;

  push_spot_bol();

  while (ffind_char(delim))
  {
    push_spot();
    if (1 == find_matching_delimiter(delim))
    {
      if (what_line() < lineno)
      {
        bol_skip_white ();
        pos = _get_point();
        pop_spot();
        break; % success
      }
      else
      {
        pop_spot();
        go_right_1();
      }
    }
    else
    {
      pop_spot();
      go_right_1();
    }
  }

  pop_spot();
  return pos;
}

% Return the delimiter in the current line plus the delimiter and its
% column position in a preceding line.
private define rust_find_delim_prev_delim_and_col()
{
  variable this_delim = NULL, prev_delim = NULL, prev_delim_col = 0;

  push_spot();
  this_delim = rust_get_delim();

  while (up(1))
  {
    bol();
    prev_delim = rust_get_delim();
    if (prev_delim != NULL) break;
  }

  bol_skip_white();
  prev_delim_col = _get_point();
  pop_spot();
  return this_delim, prev_delim, prev_delim_col;
}

% Return the point in the line to indent to
private define rust_get_indentation()
{
  variable this_delim = NULL, prev_delim = NULL, prev_delim_col = 0;

  (this_delim, prev_delim, prev_delim_col) = rust_find_delim_prev_delim_and_col();

  if (prev_delim == NULL) return 0;

  if (this_delim == "}{") this_delim = "}";
  if (prev_delim == "}{") prev_delim = "{";
  if (this_delim == "){") this_delim = ")";
  if (prev_delim == "){") prev_delim = "{";

  if (prev_delim == "if" && this_delim == "{")
    return prev_delim_col + C_BRACE;

  if (this_delim == "}")
    return rust_find_col_matching_delim('}');

  if (this_delim == ")")
    return rust_find_col_matching_delim(')');

  if (this_delim == "]")
    return rust_find_col_matching_delim(']');

  if (any(prev_delim == Rust_Block_End_Delims))
    return prev_delim_col;

  if (any(prev_delim == Rust_Block_Beg_Delims))
    return prev_delim_col + Rust_Indent;

  return NULL;
}

private define rust_indent_line()
{
  variable indentation = rust_get_indentation();

  if (indentation == NULL) return skip_white();

  bol(); trim(); insert_spaces(indentation);
}

define rust_indent_region_or_line()
{
  variable reg_endline, i = 1;

  ifnot (is_visible_mark())
    return rust_indent_line();

  check_region(0);
  reg_endline = what_line();
  pop_mark_1();

  do
  {
    flush (sprintf ("indenting buffer ... (%d%%)", (i*100)/reg_endline));
    if (eolp() and bolp()) continue;
    rust_indent_line();
    i++;
  }
  while (down(1) and what_line != reg_endline);
  clear_message();
}

define rust_newline_and_indent()
{
  bskip_white();
  push_spot(); rust_indent_line(); pop_spot();
  insert("\n");
  rust_indent_line();
}

% Edit options to rustc.
define rust_edit_rustc_opts()
{
  Rustc_Opts = read_mini("rustc options:","", strjoin(Rustc_Opts, " "));
}

% Use the rustfmt program to format the current buffer or the rustc
% program to compile and show a possible output in a window. If there
% are errors, the output will also be shown in a window. The desired
% default options to these programs should be set in e.g.
% "~/.config/rustfmt/.rustfmt.toml" for rustfmt
define rust_format_or_compile(cmd)
{
  variable cmd_line, prg, exit_status, obj, str, line = what_line();;
  variable tmpfile = make_tmp_file("rust");
  variable errfile = make_tmp_file("rust_err");
  variable errbuf = "*** errors from $cmd ***"$;
  variable outfile = sprintf("/tmp/%s", path_basename_sans_extname(whatbuf()));

  push_spot_bob(); push_mark_eob(); str = bufsubstr(); pop_spot();

  if (-1 == write_string_to_file(str, tmpfile))
    throw RunTimeError, "could not write buffer contents to $tmpfile"$;

  if (cmd == "rustfmt")
  {
    if (NULL == search_path_for_file(getenv("PATH"), "rustfmt"))
      throw RunTimeError, "rustfmt program not found";

    ifnot (get_y_or_n("format buffer with rustfmt")) return;

    obj = new_process ([cmd, tmpfile]; stderr=errfile);
  }
  if (cmd == "rustc")
  {
    if (NULL == search_path_for_file(getenv("PATH"), "rustc"))
      throw RunTimeError, "rustc program not found";

    if (strlen(Rustc_Opts))
    {
      Rustc_Opts = strtok(Rustc_Opts);
      cmd_line = ["rustc", Rustc_Opts, "-o", outfile, tmpfile];
    }
    else
      cmd_line = ["rustc", "-o", outfile, tmpfile];

    obj = new_process (cmd_line; stderr=errfile);
  }

  exit_status = obj.wait().exit_status;

  try
  {
    if (exit_status != 0)
    {
      pop2buf(errbuf);
      () = insert_file(errfile);
      set_buffer_modified_flag(0);
      most_mode();
      bob();
      return flush("type 'q' to close this window");
    }
    if (cmd == "rustfmt")
    {
      erase_buffer();
      () = insert_file(tmpfile);
      goto_line(line);
      flush("buffer formatted");
    }
    if (cmd == "rustc")
    {
      do_shell_cmd(outfile); % run the compiled object in a shell window
      set_buffer_modified_flag(0);
      trim_buffer();
      if (eobp()) call("delete_window"); % no visible output
      else
      {
        most_mode();
        bob();
      }

      flush("successfully compiled as $outfile"$);
    }
  }
  finally
  {
    () = remove(tmpfile);
    () = remove(errfile);
  }
}

% Move up and down between block levels.
private define rust_goto_level(dir)
{
  variable delim, col = 1;
  variable delims_beg = Rust_Block_Beg_Delims;
  variable delims_end = [Rust_Block_End_Delims];
  variable move = &down;

  delim = rust_get_delim();

  if (dir < 0)
  {
    ifnot (any(delim == delims_end))
      verror("not in a line with any of delimiters, \"%s\"", strjoin(delims_end, ", "));

    move = &up;
    delims_end = delims_beg;
  }
  else ifnot (any(delim == delims_beg))
    verror("not in a line with any of delimiters, \"%s\"", strjoin(delims_beg, ", "));

  bol_skip_white();
  col = what_column();

  while (@move(1))
  {
    delim = rust_get_delim();
    if (delim == NULL) continue;
    if (any(delim == delims_end))
    {
      bol_skip_white();
      if (col == what_column()) break;
    }
  }
}

define rust_goto_top_of_level()
{
  rust_goto_level(-1);
}

define rust_goto_end_of_level()
{
  rust_goto_level(1);
}

ifnot (keymap_p (Mode)) make_keymap(Mode);
undefinekey_reserved ("f", Mode);
definekey_reserved ("rust_format_or_compile\(\"rustfmt\"\)", "f", Mode);
undefinekey_reserved ("o", Mode);
definekey_reserved ("rust_edit_rustc_opts", "o", Mode);
undefinekey(Key_F9, Mode);
definekey("rust_format_or_compile\(\"rustc\"\)", Key_F9, Mode);
undefinekey("}", Mode);
definekey("c_insert_ket", "}", Mode);
undefinekey("{", Mode);
definekey("c_insert_bra", "{", Mode);
undefinekey (Key_Shift_Up, Mode);
undefinekey (Key_Shift_Down, Mode);

private define rust_menu(menu)
{
  menu_append_item (menu, "Format Buffer w/rustfmt", "rust_format_or_compile\(\"rustfmt\"\)");
  menu_append_item (menu, "Compile buffer w/rustc", "rust_format_or_compile\(\"rustc\"\)");
  menu_append_item (menu, "Edit options to rustc", "rust_edit_rustc_opts");
}

define rust_mode()
{
  add_kws_to_table(Rust_Loop_Cond_Keywords, Syntax_Table, 0);
  add_kws_to_table(Rust_Reserved_Keywords, Syntax_Table, 1);
  use_syntax_table(Syntax_Table);
  set_comment_info(Mode, "// ", "", 0);
  set_mode(Mode, 4);
  mode_set_mode_info (Mode, "init_mode_menu", &rust_menu);
  use_keymap (Mode);
  set_buffer_hook("newline_indent_hook", "rust_newline_and_indent");
  set_buffer_hook("indent_hook", "rust_indent_region_or_line");
  set_buffer_hook("backward_paragraph_hook", &rust_goto_top_of_level);
  set_buffer_hook("forward_paragraph_hook", &rust_goto_end_of_level);
  run_mode_hooks("rust_mode_hook");
}
