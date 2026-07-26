% wrap.sl, a Jed mode to wrap commented lines or paragraphs in
% computer language modes as well as formatting string variables.
% Author: Morten Bo Johansen, <mortenbo at hotmail dot com>
% License: GPLv3
% Version 0.5.1 (2026/08/26)
require("comments");
require("pcre");

% accessible to parent mode
variable Cmt_Char_Beg = "";
variable Cmt_Char_End = "";

private define is_par_sep()
{
  variable cmt_char_esc = str_quote_string(Cmt_Char_Beg, "*\\", '\\'); % C, *roff
  push_spot_bol();
  skip_white();
  (eolp() || eobp() || not re_looking_at(cmt_char_esc));
  pop_spot();
}

private define str_make_spaces(n)
{
  variable s = "";
  loop (n) s += " ";
  return s;
}

private define strip_cmt_chars(line)
{
  variable beg, end, match, re;
  
  beg = str_quote_string(Cmt_Char_Beg, "*\\", '\\'); % "/*", .\" (C or groff)
  end = str_quote_string(Cmt_Char_End, "*\\", '\\');
  re = "^\\h*$beg(.*?)(?:$end)?\\h*$"$;
  match = pcre_matches(re, line);
  
  if (match == NULL || length(match) == 0) return line;
  return match[-1];
}

% Get the comment character for the buffer if defined. Otherwise set it to
% an empty string.
private define get_cmt_char()
{
  variable cmt_info, cmt_char_beg = "", cmt_char_end = "";

  cmt_info = get_comment_info();

  if (NULL != cmt_info)
  {
    cmt_char_beg = get_struct_field(cmt_info, "cbeg");
    cmt_char_end = get_struct_field(cmt_info, "cend");
  }

  ifnot (blocal_var_exists("cmt_char_beg"))
    define_blocal_var("cmt_char_beg", cmt_char_beg);

  ifnot (blocal_var_exists("cmt_char_end"))
    define_blocal_var("cmt_char_end", cmt_char_end);

  set_blocal_var(cmt_char_beg, "cmt_char_beg");
  set_blocal_var(cmt_char_end, "cmt_char_end");

  return (get_blocal_var("cmt_char_beg"), get_blocal_var("cmt_char_end"));
}

private define wrap_switch_buffer_hook(oldbuf)
{
  (Cmt_Char_Beg, Cmt_Char_End) = get_cmt_char();
}

% Wrap commented lines as you type. New line always indented to
% level of the current line, like with WRAP_INDENTS = 1. 
private define wrapok_hook ()
{
  variable indent_pos = 0, indent_str = "", line_is_cmt, cmt_char_esc;

  ifnot (strlen(Cmt_Char_Beg)) return 0;

  push_spot();
  cmt_char_esc = str_quote_string(Cmt_Char_Beg, "*\\", '\\'); % C, *roff
  indent_pos = strlen(string_matches(line_as_string(), "^ *", 1)[0]);
  line_is_cmt = string_match(line_as_string(), "^ *$cmt_char_esc"$, 1);
  pop_spot();

  ifnot (line_is_cmt) return 0;

  indent_str = str_make_spaces(indent_pos);

  if (LAST_CHAR == 32) return 0;
  insert(strcat(Cmt_Char_End, "\n", indent_str, Cmt_Char_Beg));
  return 1;
}

% Tie the keybinding for the format_paragraph() function to the
% wrap_paragraph_or_string() function instead.
private define set_wrap_key()
{
  variable n, key, map;
  variable fun = "format_paragraph";

  map = what_keymap();
  n = which_key(fun);
  if (n == 0) key = "^[Q"; % hard coded default
  else
  {
    loop (n)
      key = ();
  }

  if (n > 1)
    flush("Note: More than 1 key tied to \"$fun\", using \"$key\""$);

  undefinekey(key, map);
  definekey("wrap_paragraph_or_string", key, map);
}

% Mark a commented paragraph.
private define wrap_mark_paragraph()
{
  variable cmt_re, cmt_char_esc;

  cmt_char_esc = str_quote_string(Cmt_Char_Beg, "*\\", '\\');
  cmt_re = "^[ \t]*$cmt_char_esc[ \t]*"$;
  bol();

  % If not in a line beginning with a comment character, then do nothing.
  ifnot (re_looking_at(cmt_re))
    return -1;
  
  do
  {
    ifnot (up(1)) break;
    bol();
  }
  while (re_looking_at(cmt_re) && not is_par_sep());

  ifnot ((bobp() || is_par_sep()) && re_looking_at(cmt_re))
    go_down_1();

  push_visible_mark();

  do
  {
    ifnot (down(1))
    {
      eol();
      break;
    }
  }
  while (re_looking_at(cmt_re) && not is_par_sep());

  if (is_par_sep()) go_left_1();
  else eol();

  return 1;
}

% Wrap the contents of a string variable or a commented paragraph/line.
define wrap_paragraph_or_string()
{
  variable org_str = "", str = "", indent_str = "";
  variable lines, wchars, incr, cmt_char_esc, e;
  variable indent_pos = 0, i = 0, j = 0;
  variable args = __pop_list(_NARGS);
  variable newln = 10, space = 32;
  variable wrap = WRAP;

  if (length(args)) % only string variable operation
  {
    variable msg = "Usage: strfmt(str, wrap_col, [indent_pos])";

    if (length(args) < 2 || length(args) > 3)
      return flush(msg);

    org_str = args[0];
    wrap = args[1];

    ifnot (typeof(wrap) == Int_Type && typeof(org_str) == String_Type)
      return flush(msg);

    if (length(args) == 3)
      indent_pos = args[2];
    
    % with string variables we want e.g. strfmt(str, 25, 70) to create a
    % string where each line is actually at most 25 characters long, padded
    % with spaces to column 70 without curtailing the line lengths to WRAP -
    % column.
    wrap += indent_pos;
    incr = wrap;
  }
  else % only buffer operation
  {
    push_spot();

    if (-1 == wrap_mark_paragraph())
      return pop_spot();

    narrow_to_region();
    bob();
    skip_white();
    indent_pos = _get_point();
    mark_buffer();
    org_str = bufsubstr_delete();
  }

  try (e) % both string variable and buffer operation
  {
    wrap -= 1; % like format_paragraph
    lines = strtrim(strchop(org_str, '\n', 0));
    str = strjoin(lines, "\n");
    indent_str = str_make_spaces(indent_pos);

    if (indent_pos > 0)
      wrap -= indent_pos;

    if (strlen(Cmt_Char_Beg))
    {
      lines = strchop(str, '\n', 0);
      lines = array_map(String_Type, &strip_cmt_chars, lines);
      str = strjoin(lines, "\n");
    }

    wrap -= strlen(Cmt_Char_Beg) + strlen(Cmt_Char_End);
    incr = wrap;
    wchars = string_to_wchars(strtrim(str));

    % the wrapping routine.
    _for i (0, length(wchars)-1, 1)
    {
      % skip empty lines == paragraph separators
      if (i > 0 && wchars[i] == newln && wchars[i - 1] == newln)
      {
        wrap = i + incr;
        continue;
      }

      if (wchars[i] == newln && wchars[i + 1] != newln)
        wchars[i] = space;

      if (wchars[i] == space)
      {
        if (i >= wrap)
        {
          wchars[j] = newln;
          wrap = j + incr + 1;
        }

        j = i;
      }

      if (i >= wrap)
        wchars[j] = newln;
    }

    str = wchars_to_string(wchars);
    lines = strchop(str, '\n', 0);
    lines = array_map(String_Type, &strcat, indent_str, Cmt_Char_Beg, lines,
                      Cmt_Char_End);

    str = strjoin(lines, "\n");

    if (length(args))
      return str;
    else
    {
      pop_spot();
      trim();
      insert(str);
      bob();
      cmt_char_esc = str_quote_string(Cmt_Char_Beg, "\\", '\\');
      skip_chars("\t $cmt_char_esc"$);
      widen();
    }
  }
  catch AnyError:
  {
    if (length(args) == 0) % buffer operation only
    {
      pop_spot();

      % if error happened after the region was deleted and before the
      % formatted string was inserted, then restore the original region;
      if (bobp() && eobp()) 
        insert(org_str);

      bob();
      widen();
    }
    
    throw e.error, e.message;
  }
}

% An alias function to wrap_paragraph_or_string(), just to conform to jed's
% naming convention of using "str.*" for functions that work on string
% variables.
define strfmt()
{
  variable args = __pop_list(_NARGS);

  wrap_paragraph_or_string(__push_list(args));
}

define wrap_mode()
{
  (Cmt_Char_Beg, Cmt_Char_End) = get_cmt_char();
  set_wrap_key();
  set_buffer_hook("wrapok_hook", &wrapok_hook);
  append_to_hook ("_jed_switch_active_buffer_hooks", &wrap_switch_buffer_hook);
}

provide("wrap");
