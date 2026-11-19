defmodule PhoenixKitTemplatesEditor.Body do
  @moduledoc """
  The body of a letter on its way between its files and the Leaf editor.

  The stored body is the Markdown file; the text file is derived from it on a
  save. Three things stand between that Markdown and what Leaf holds:

    * **Line breaks.** Leaf draws a bare newline as a line break (it renders
      with hard breaks on) and writes a `<br>` back as a bare newline. The
      renderer an email is made with does not: a bare newline is a space
      there, so a signature of four short lines would run together. `to_editor/1`
      turns the explicit breaks of a stored file (`\\` or two spaces at the end
      of a line) into bare newlines for Leaf, `from_editor/1` writes explicit
      ones back (`\\`, or two spaces after a line that ends with a bare web
      address, which the renderer's autolink would take a backslash into),
      between two lines of one paragraph only — never before a
      list item, a heading, a quote, a table row, a rule or a code fence, where
      a break is no break.
    * **Placeholders.** Leaf's visual mode percent-encodes `{{url}}` in a
      link or image target (`%7B%7Burl%7D%7D`) and, since 0.10, writes typed
      text back with Markdown escapes (`{{_x}}` as `{{\\_x}}`).
      `restore_placeholders/1` undoes both, and nothing else.
    * **A text-only letter** has no Markdown. `from_text/1` makes some that
      reads back as the same text: `from_text/1` → `from_editor/1` → the derived
      text (`PhoenixKitTemplatesEditor.Converters.to_text/3`) is the text
      again for an ordinary letter. Every character a renderer would take for
      Markdown is escaped (`*`, `_` next to a non-word, a backtick, `[`, `<`,
      `~`, a backslash, a line that starts like a list, a heading, a quote or a
      numbered item; not inside a web address) and so is what its smart punctuation would change (`"`, `'`,
      `--`, `...`); an entity written in the text (`&amp;`) too. Placeholders are
      never touched.

  ## Where the round trip is not exact

  A Markdown paragraph cannot keep: several blank lines in a row (they come
  back as one), the blank lines around the text and its final newline,
  spaces at the end of a line, and the indentation of a line. A line of
  spaces is a blank line. Everything else — paragraphs, single line breaks,
  placeholders alone on a line, lines that start with `-`, `+`, `*`, `#`,
  `>` or a number, underscores, asterisks, e-mail addresses, `|`, quotes,
  entities, non-ASCII text — comes back as it was.
  """

  alias PhoenixKit.Templates.Substitution

  # Compiled once, when the module is loaded, and read from `:persistent_term`:
  # on Erlang/OTP 28 a `~r` kept in a module attribute is compiled again
  # at every use, which on a long body costs
  # more than the matching itself.
  @regexes [
    fence: {~S"\A {0,3}(?:```|~~~)", ""},
    heading: {~S"\A {0,3}\#{1,6}(?:[ \t]|\z)", ""},
    thematic: {~S"\A {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*\z", ""},
    setext: {~S"\A {0,3}=+[ \t]*\z", ""},
    table_delimiter:
      {~S"\A[ \t]*(?:\|[ \t]*)?:?-+:?(?:[ \t]*\|[ \t]*:?-+:?)*(?:[ \t]*\|)?[ \t]*\z", ""},
    list_item: {~S"\A[ \t]*(?:[-+*](?:[ \t]|\z)|\d{1,9}[.)](?:[ \t]|\z))", ""},
    html_block: {~S"\A {0,3}(?:<\/?[A-Za-z][A-Za-z0-9-]*(?:[ \t\/>]|\z)|<[!?])", ""},
    table_row: {~S"\A[ \t]*\|", ""},
    target: {~S"(\]\()(<[^<>\n]*>|(?:[^\s()]|\([^\s()]*\))*)", ""},
    encoded: {~S"((?:%7B){2,3})((?:%20)*[A-Za-z0-9_.\-]*(?:%20)*)((?:%7D){2,3})", "i"},
    reference: {~S"^( {0,3}\[[^\]\n]*\]:[ \t]*)(<[^<>\n]*>|\S+)", "m"},
    braced: {~S"\{\{\{?(?:[^{}\n])*?\}\}\}?", ""},
    escape: {~S"\\([!-\/:-@\[-`{-~])", ""},
    room: {~S"\n(?:[ \t]*\n){2,}", ""},
    address: {~S"(?:https?:\/\/|www\.)[^\s<]+", ""},
    block_name: {~S"\A\{\{\{?\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}\}?\z", ""},
    dashes: {~S"\A[-:| \t]+\z", ""},
    numbered: {~S"\A(\d{1,9})([.)])(.*)\z", "s"},
    entity: {~S"\A#?\w+;", ""},
    word_char: {~S"\A[\p{L}\p{N}]\z", "u"}
  ]

  # The same for the patterns a line is asked about first: a list of binaries
  # given to `:binary.match/2` is compiled at every call, which costs more
  # than the match.
  @patterns [
    braces: ["{{"],
    dash: ["-"],
    address_start: ["://", "www.", "WWW.", "Www."],
    address_word: ["http", "www."]
  ]

  @on_load :compile_regexes

  @doc false
  def compile_regexes do
    for {name, {source, options}} <- @regexes do
      :persistent_term.put({__MODULE__, name}, Regex.compile!(source, options))
    end

    for {name, patterns} <- @patterns do
      :persistent_term.put({__MODULE__, name}, :binary.compile_pattern(patterns))
    end

    :ok
  end

  defp rx(name), do: :persistent_term.get({__MODULE__, name})

  # Whether `text` holds one of the patterns of `name` (`@patterns`).
  defp has?(text, name),
    do: :binary.match(text, :persistent_term.get({__MODULE__, name})) != :nomatch

  # A line class can only match when the first character that is no blank is
  # one of a few: asking that first (a byte of the line) spares the regular
  # expression for every line that is plain text, a quotation or a list.
  @gates %{
    fence: ~c"`~",
    heading: ~c"#",
    thematic: ~c"-*_",
    setext: ~c"=",
    table_delimiter: ~c"|:-",
    list_item: ~c"-+*0123456789",
    html_block: ~c"<",
    table_row: ~c"|"
  }

  defp is?(:quote, line), do: quote_rest(line, 0) != nil

  defp is?(name, line) do
    case first_char(line) do
      nil -> false
      char -> :lists.member(char, Map.fetch!(@gates, name)) and Regex.match?(rx(name), line)
    end
  end

  defp blank?(line), do: first_char(line) == nil

  defp first_char(<<c, rest::binary>>) when c in [?\s, ?\t], do: first_char(rest)
  defp first_char(<<c, _rest::binary>>), do: c
  defp first_char(<<>>), do: nil

  # No two quantifiers that can take the same space in a row: a line of
  # blanks is read in one pass, not in as many as it has characters squared.
  # A list item at any indent: a nested one is indented past its parent's marker.
  # A tag, a comment or a declaration — not `<https://x>` or `<a@b.ee>`, which are links.

  ## Placeholders

  @doc """
  `markdown` with the placeholders Leaf damaged put back: `%7B%7B…%7D%7D`
  (any case of the hex digits, blanks inside as `%20`) in a link or image
  target, or in the address of a reference definition, becomes `{{…}}`
  (`{{{…}}}` for three), and a backslash before a character inside a
  `{{…}}` or `{{{…}}}` that is a placeholder once it is gone is removed.
  Nothing else is changed; applying it twice changes nothing more.
  """
  @spec restore_placeholders(String.t()) :: String.t()
  def restore_placeholders(markdown) when is_binary(markdown) do
    markdown |> decode_targets() |> unescape_placeholders()
  end

  # A link or image target `](…)`, and the address of a reference definition
  # (`[1]: …`).
  defp decode_targets(markdown) do
    markdown
    |> then(
      &Regex.replace(rx(:target), &1, fn _whole, open, target -> open <> decode(target) end)
    )
    |> then(
      &Regex.replace(rx(:reference), &1, fn _whole, open, target -> open <> decode(target) end)
    )
  end

  defp decode(target), do: Regex.replace(rx(:encoded), target, &decode_braces/4)

  defp decode_braces(whole, open, name, close) do
    count = div(byte_size(open), 3)

    if count == div(byte_size(close), 3),
      do: String.duplicate("{", count) <> decode_blanks(name) <> String.duplicate("}", count),
      else: whole
  end

  defp decode_blanks(name), do: String.replace(name, ["%20"], " ")

  defp unescape_placeholders(markdown) do
    Regex.replace(rx(:braced), markdown, fn span ->
      plain = Regex.replace(rx(:escape), span, "\\1")

      if plain != span and Substitution.split(plain) == ["", plain, ""], do: plain, else: span
    end)
  end

  ## Line breaks

  @doc """
  The stored Markdown as Leaf is given it: an explicit line break (`\\` or two
  spaces at the end of a line) between two lines of a paragraph is a bare
  newline, as Leaf writes one.
  """
  @spec to_editor(String.t()) :: String.t()
  def to_editor(markdown) when is_binary(markdown) do
    markdown |> lines() |> map_breaks(&drop_break/1, []) |> Enum.join("\n")
  end

  @doc """
  What Leaf wrote as the Markdown to store: the placeholders restored
  (`restore_placeholders/1`) and an explicit `\\` at the end of every line of
  a paragraph that is followed by another line of it.

  `block_placeholders` are the variables a send fills with a block of their
  own (a list): a line that ends with such a placeholder gets no break after
  it, and a line that starts with one none before it (so a line that is only
  the placeholder has neither, nor its neighbours) — the block is put in
  place of the placeholder with the line break next to it, and a `\\` left
  on the other side would show in the letter. The text version is not made
  from that Markdown but from `from_editor/1` without the list, which keeps
  every line break, so the text still has the line.
  """
  @spec from_editor(String.t(), [String.t()]) :: String.t()
  def from_editor(markdown, block_placeholders \\ []) when is_binary(markdown) do
    markdown
    |> restore_placeholders()
    |> lines()
    |> map_breaks(&add_break/1, block_placeholders)
    |> Enum.join("\n")
  end

  defp lines(markdown), do: markdown |> String.replace("\r\n", "\n") |> String.split("\n")

  # `fun` is given a line that is followed by a line of its paragraph, and
  # returns it as it is to be written. Lines of a fenced code block, the
  # fences, and lines before or after a block are not given.
  defp map_breaks(lines, fun, blocks), do: map_breaks(lines, false, false, fun, blocks, [])

  defp map_breaks([line], _fenced?, _in_list?, _fun, _blocks, acc),
    do: Enum.reverse([line | acc])

  defp map_breaks([line, next | rest], fenced?, in_list?, fun, blocks, acc) do
    fence? = not word_start?(line) and is?(:fence, line)
    in_list? = list_state(line, in_list?)

    line =
      if not fenced? and not fence? and break_between?(line, next, blocks, in_list?),
        do: fun.(line),
        else: line

    map_breaks([next | rest], fenced? != fence?, in_list?, fun, blocks, [line | acc])
  end

  defp map_breaks([], _fenced?, _in_list?, _fun, _blocks, acc), do: Enum.reverse(acc)

  # Inside a list item from its marker to the next blank line: a line indented
  # four or more spaces there continues the item (or is a nested item), it is not code.
  defp list_state(line, in_list?) do
    cond do
      word_start?(line) -> in_list?
      blank?(line) -> false
      is?(:list_item, line) -> true
      true -> in_list?
    end
  end

  defp break_between?(line, next, blocks, in_list?) do
    {_starts, ends?} = block_edges(line, blocks)
    {starts?, _ends} = block_edges(next, blocks)

    not ends? and not starts? and
      ((breakable?(line, in_list?) and plain?(next)) or quoted_pair?(line, next))
  end

  # Two lines of one quotation: the text after the `>`.
  defp quoted_pair?(line, next) do
    is?(:quote, line) and is?(:quote, next) and
      breakable?(unquote_line(line), false) and plain?(unquote_line(next))
  end

  # What follows a quote mark and the one blank after it (`>` and ` {0,3}>[ \t]?`).
  defp unquote_line(line) do
    case quote_rest(line, 0) do
      nil -> line
      <<c, rest::binary>> when c in [?\s, ?\t] -> rest
      rest -> rest
    end
  end

  # A quotation's mark: up to three spaces, then `>`; what follows it, or nil.
  defp quote_rest(<<?\s, rest::binary>>, count) when count < 3, do: quote_rest(rest, count + 1)
  defp quote_rest(<<?>, rest::binary>>, _count), do: rest
  defp quote_rest(_line, _count), do: nil

  # Whether a line starts and whether it ends with the placeholder of a
  # variable the send fills with a block (a quotation's `>` marks do not
  # count). The send puts the block in place of the placeholder and takes the
  # line break next to it, so a `\` on the other side of that break would be
  # left behind, in front of the block or after it.
  defp block_edges(_line, []), do: {false, false}

  defp block_edges(line, blocks) do
    if has?(line, :braces),
      do: line |> unquote_up_to(3) |> placeholder_edges(blocks),
      else: {false, false}
  end

  defp unquote_up_to(line, 0), do: line

  defp unquote_up_to(line, levels) do
    if is?(:quote, line),
      do: line |> unquote_line() |> unquote_up_to(levels - 1),
      else: line
  end

  defp placeholder_edges(line, blocks) do
    case Substitution.split(line) do
      [_only] ->
        {false, false}

      parts ->
        {
          blank?(hd(parts)) and block_name?(Enum.at(parts, 1), blocks),
          blank?(List.last(parts)) and block_name?(Enum.at(parts, -2), blocks)
        }
    end
  end

  defp block_name?(placeholder, blocks) do
    case Regex.run(rx(:block_name), placeholder) do
      [_whole, name] -> name in blocks
      nil -> false
    end
  end

  # A line a paragraph's line break can follow: not blank, not a block of
  # its own, not indented as code (a nested list item is indented, not code).
  defp breakable?(line, in_list?), do: word_start?(line) or breakable_block?(line, in_list?)

  defp breakable_block?(line, in_list?) do
    not blank?(line) and
      (in_list? or is?(:list_item, line) or
         not String.starts_with?(line, ["    ", "\t"])) and
      not Enum.any?(
        [
          :heading,
          :thematic,
          :setext,
          :table_delimiter,
          :table_row,
          :html_block
        ],
        &is?(&1, line)
      )
  end

  # A line that continues a paragraph: not blank, not the start of a block —
  # a nested list item at any indent is one.
  defp plain?(line), do: word_start?(line) or plain_block?(line)

  defp plain_block?(line) do
    not blank?(line) and
      not Enum.any?(
        [
          :fence,
          :heading,
          :thematic,
          :setext,
          :table_delimiter,
          :table_row,
          :html_block,
          :list_item,
          :quote
        ],
        &is?(&1, line)
      )
  end

  # A line that starts with a letter (or any non-ASCII character) is no block
  # of any kind: the common line is told so without a regular expression.
  defp word_start?(<<c, _rest::binary>>), do: c in ?a..?z or c in ?A..?Z or c >= 128
  defp word_start?(<<>>), do: false

  # A line that ends with a bare web address gets two spaces, not `\`: the
  # renderer's autolink takes a trailing backslash into the address (the link
  # would end in `\` and no break would be drawn).
  defp add_break(line) do
    cond do
      hard_break?(line) -> line
      ends_with_address?(line) -> trim_trailing_blanks(line) <> "  "
      true -> trim_trailing_blanks(line) <> "\\"
    end
  end

  # The last blank-separated word of the line holds `http://`, `https://` or
  # `www.` (any case), not an `<…>` link. Linear in the line's length: one split, one match.
  defp ends_with_address?(line) do
    has?(line, :address_start) and last_word_address?(line)
  end

  defp last_word_address?(line) do
    last = line |> trim_trailing_blanks() |> String.split([" ", "\t"]) |> List.last()

    not angle_link?(last) and
      :binary.match(String.downcase(last), ["http://", "https://", "www."]) != :nomatch
  end

  # `<https://…>` is no bare address: the `>` ends it, a backslash after is a break.
  defp angle_link?(<<"<", _rest::binary>> = word), do: String.ends_with?(word, ">")
  defp angle_link?(_word), do: false

  defp drop_break(line) do
    cond do
      odd_backslashes?(line) -> binary_part(line, 0, byte_size(line) - 1)
      String.ends_with?(line, "  ") -> trim_trailing_blanks(line)
      true -> line
    end
  end

  defp hard_break?(line), do: odd_backslashes?(line) or String.ends_with?(line, "  ")

  # A backslash before a newline is a break; two are a backslash.
  defp odd_backslashes?(line), do: line |> trailing_backslashes(byte_size(line), 0) |> rem(2) == 1

  defp trailing_backslashes(line, size, count) when size > 0 do
    if :binary.at(line, size - 1) == ?\\,
      do: trailing_backslashes(line, size - 1, count + 1),
      else: count
  end

  defp trailing_backslashes(_line, 0, count), do: count

  # Spaces and tabs off the ends of a line, in one pass over it.
  defp trim_trailing_blanks(line), do: trim_trailing_blanks(line, byte_size(line))

  defp trim_trailing_blanks(line, size) when size > 0 do
    if :binary.at(line, size - 1) in [?\s, ?\t],
      do: trim_trailing_blanks(line, size - 1),
      else: binary_part(line, 0, size)
  end

  defp trim_trailing_blanks(_line, 0), do: ""

  defp trim_leading_blanks(<<c, rest::binary>>) when c in [?\s, ?\t],
    do: trim_leading_blanks(rest)

  defp trim_leading_blanks(line), do: line

  ## A text-only letter

  @doc """
  The Markdown a text-only letter is opened in Leaf with (see the moduledoc):
  blank lines separate paragraphs, a single newline stays a line break, and
  what the renderer would read as Markdown is escaped. Leading and trailing
  spaces of a line are dropped, and so are the blank lines before the first
  paragraph and after the last. A run of blank lines between two paragraphs
  is kept as it is: room left on purpose (`room?/1`).
  """
  @spec from_text(String.t()) :: String.t()
  def from_text(text) when is_binary(text) do
    text
    |> lines()
    |> Enum.map(&(&1 |> trim_leading_blanks() |> trim_trailing_blanks()))
    |> Enum.chunk_by(&(&1 == ""))
    |> Enum.drop_while(&(hd(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(hd(&1) == ""))
    |> Enum.reverse()
    |> Enum.map_join("\n", fn
      ["" | _] = blanks -> Enum.join(blanks, "\n")
      paragraph -> Enum.map_join(paragraph, "\n", &escape_line/1)
    end)
  end

  ## Room left on purpose

  # Two or more blank lines in a row between two paragraphs.

  @doc """
  Whether `markdown` has room left on purpose: more than one blank line in a
  row between two paragraphs — the place a writer types into in a letter that
  is a frame. Markdown reads any such run as one paragraph break, so a visual
  editor cannot hold it; the source and the text version do.
  """
  @spec room?(String.t()) :: boolean()
  def room?(markdown) when is_binary(markdown), do: Regex.match?(rx(:room), String.trim(markdown))

  @doc """
  The text of `markdown` with its room kept: `convert` is given each stretch
  between two runs of blank lines, and the runs go back between the results
  as they were. `{:error, reason}` of the first stretch that fails.
  """
  @spec keeping_room(String.t(), (String.t() -> {:ok, String.t()} | {:error, term()})) ::
          {:ok, String.t()} | {:error, term()}
  def keeping_room(markdown, convert) when is_binary(markdown) and is_function(convert, 1) do
    rx(:room)
    |> Regex.split(markdown, include_captures: true)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn
      {run, index}, {:ok, done} when rem(index, 2) == 1 ->
        {:cont, {:ok, [blank_lines(run) | done]}}

      {stretch, _index}, {:ok, done} ->
        case convert.(stretch) do
          {:ok, text} -> {:cont, {:ok, [String.trim_trailing(text, "\n") | done]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
    |> case do
      {:ok, parts} -> {:ok, parts |> Enum.reverse() |> Enum.join()}
      error -> error
    end
  end

  # The run with whatever spaces its blank lines held taken out.
  defp blank_lines(run),
    do: String.duplicate("\n", run |> String.graphemes() |> Enum.count(&(&1 == "\n")))

  defp escape_line(line) do
    # Only a `-` is told apart by it, so a line without one need not ask.
    all_dashes? = has?(line, :dash) and Regex.match?(rx(:dashes), line)

    line
    |> split_placeholders()
    |> Enum.with_index()
    |> Enum.map_join(fn
      {placeholder, index} when rem(index, 2) == 1 -> placeholder
      {text, index} -> escape_text(text, index == 0, all_dashes?)
    end)
  end

  defp split_placeholders(line),
    do: if(has?(line, :braces), do: Substitution.split(line), else: [line])

  # A web address is left as it is: a renderer takes it from the source
  # with its backslashes, so an escaped `~` or `*` would show in the text.
  defp escape_text(text, first?, all_dashes?) do
    text
    |> split_addresses()
    |> Enum.with_index()
    |> Enum.map_join(fn
      {address, index} when rem(index, 2) == 1 -> address
      {piece, 0} when first? -> escape_start(piece, all_dashes?)
      {piece, _index} -> escape_inline(piece, nil, all_dashes?, [])
    end)
  end

  defp split_addresses(text) do
    if has?(text, :address_word),
      do: Regex.split(rx(:address), text, include_captures: true),
      else: [text]
  end

  # The start of a line: what would open a heading, quote, list or rule.
  defp escape_start("", _all_dashes?), do: ""

  defp escape_start(<<c, rest::binary>>, all_dashes?) when c in [?#, ?>, ?-, ?+, ?=] do
    "\\" <> <<c>> <> escape_inline(rest, <<c>>, all_dashes?, [])
  end

  defp escape_start(<<c, _rest::binary>> = text, all_dashes?) when c in ?0..?9 do
    case Regex.run(rx(:numbered), text) do
      [_whole, digits, delimiter, rest] ->
        digits <> "\\" <> delimiter <> escape_inline(rest, delimiter, all_dashes?, [])

      nil ->
        escape_inline(text, nil, all_dashes?, [])
    end
  end

  defp escape_start(text, all_dashes?), do: escape_inline(text, nil, all_dashes?, [])

  defp escape_inline("", _prev, _all_dashes?, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp escape_inline(<<c::utf8, rest::binary>>, prev, all_dashes?, acc) do
    char = <<c::utf8>>
    escaped = if escape?(char, prev, rest, all_dashes?), do: "\\" <> char, else: char
    escape_inline(rest, char, all_dashes?, [escaped | acc])
  end

  # Not valid UTF-8: left as it is (the editor refuses such a file anyway).
  defp escape_inline(<<byte, rest::binary>>, _prev, all_dashes?, acc),
    do: escape_inline(rest, nil, all_dashes?, [<<byte>> | acc])

  defp escape?(char, _prev, _rest, _all_dashes?)
       when char in ["\\", "*", "`", "[", "<", "~", "\"", "'"],
       do: true

  defp escape?("_", prev, rest, _all_dashes?), do: not (word?(prev) and word?(first(rest)))

  defp escape?("&", _prev, rest, _all_dashes?), do: Regex.match?(rx(:entity), rest)

  defp escape?("-", prev, rest, all_dashes?),
    do: all_dashes? or prev == "-" or String.starts_with?(rest, "-")

  defp escape?(".", _prev, rest, _all_dashes?), do: String.starts_with?(rest, "..")

  defp escape?(_char, _prev, _rest, _all_dashes?), do: false

  defp first(""), do: nil
  defp first(<<c::utf8, _rest::binary>>), do: <<c::utf8>>
  defp first(<<byte, _rest::binary>>), do: <<byte>>

  defp word?(nil), do: false
  defp word?(char), do: Regex.match?(rx(:word_char), char)
end
