defmodule Elasticlunr.Pipeline.Stemmer do
  @moduledoc false

  alias Elasticlunr.Token

  @behaviour Elasticlunr.Pipeline

  @step_2_list %{
    "ational" => "ate",
    "tional" => "tion",
    "enci" => "ence",
    "anci" => "ance",
    "izer" => "ize",
    "bli" => "ble",
    "alli" => "al",
    "entli" => "ent",
    "eli" => "e",
    "ousli" => "ous",
    "ization" => "ize",
    "ation" => "ate",
    "ator" => "ate",
    "alism" => "al",
    "iveness" => "ive",
    "fulness" => "ful",
    "ousness" => "ous",
    "aliti" => "al",
    "iviti" => "ive",
    "biliti" => "ble",
    "logi" => "log"
  }

  @step_3_list %{
    "icate" => "ic",
    "ative" => "",
    "alize" => "al",
    "iciti" => "ic",
    "ical" => "ic",
    "ful" => "",
    "ness" => ""
  }

  @consonant "[^aeiou]"
  @vowel "[aeiouy]"

  @consonant_sequence "#{@consonant}[^aeiouy]*"
  @vowel_sequence "#{@vowel}[aeiou]*"

  # [C]VC... is m>0
  @mgr0 "^(#{@consonant_sequence})?#{@vowel_sequence}#{@consonant_sequence}"
  # [C]VC[V] is m=1
  @meq1 "^(#{@consonant_sequence})?#{@vowel_sequence}#{@consonant_sequence}(#{@vowel_sequence})?$"
  # [C]VCVC... is m>1
  @mgr1 "^(#{@consonant_sequence})?#{@vowel_sequence}#{@consonant_sequence}#{@vowel_sequence}#{
          @consonant_sequence
        }"
  # vowel in stem
  @s_v "^(#{@consonant_sequence})?#{@vowel}"

  @re_mgr0 Regex.compile!(@mgr0)
  @re_mgr1 Regex.compile!(@mgr1)
  @re_meq1 Regex.compile!(@meq1)
  @re_s_v Regex.compile!(@s_v)

  @re_1a ~r/^(.+?)(ss|i)es$/
  @re2_1a ~r/^(.+?)([^s])s$/
  @re_1b ~r/^(.+?)eed$/
  @re2_1b ~r/^(.+?)(ed|ing)$/
  @re_1b_2 ~r/.$/
  @re2_1b_2 ~r/(at|bl|iz)$/
  @re3_1b_2 ~r/([^aeiouylsz])\1$/
  @re4_1b_2 Regex.compile!("^#{@consonant_sequence}#{@vowel}[^aeiouwxy]$")

  @re_1c ~r/^(.+?[^aeiou])y$/
  @step_2_list_keys Enum.map(@step_2_list, &elem(&1, 0)) |> Enum.join("|")
  @re_2 Regex.compile!("^(.+?)(#{@step_2_list_keys})$")

  @re_3 ~r/^(.+?)(icate|ative|alize|iciti|ical|ful|ness)$/

  @re_4 ~r/^(.+?)(al|ance|ence|er|ic|able|ible|ant|ement|ment|ent|ou|ism|ate|iti|ous|ive|ize)$/
  @re2_4 ~r/^(.+?)(s|t)(ion)$/

  @re_5 ~r/^(.+?)e$/
  @re_5_1 ~r/ll$/
  @re3_5 Regex.compile!("^#{@consonant_sequence}#{@vowel}[^aeiouwxy]$")

  @impl true
  def call(%Token{token: str} = token, _tokens) do
    with true <- String.length(str) >= 3,
         {str, first_chr} <- check_first_chr(str),
         {str, _opts} <- step_1a(str, %{re: @re_1a, re2: @re2_1a}),
         {str, opts} <- step_1b(str, %{re: @re_1b, re2: @re2_1b}),
         {str, opts} <- step_1c(str, %{opts | re: @re_1c}),
         {str, opts} <- step_2(str, %{opts | re: @re_2}),
         {str, opts} <- step_3(str, %{opts | re: @re_3}),
         {str, opts} <- step_4(str, %{opts | re: @re_4, re2: @re2_4}),
         {str, opts} <- step_5(str, %{opts | re: @re_5}),
         {str, _opts} <- last_step(str, %{opts | re: @re_5_1, re2: @re_mgr1}) do
      str =
        case first_chr == "y" do
          false ->
            str

          true ->
            str_length = String.length(str)
            first_chr = String.downcase(first_chr)
            remaining_str = String.slice(str, 1, str_length - 1)
            "#{first_chr}#{remaining_str}"
        end

      Token.update(token, token: str)
    else
      false ->
        str
    end
  end

  defp check_first_chr(str) do
    first_chr = String.slice(str, 0..0)

    str =
      if first_chr == "y" do
        str_length = String.length(str)
        first_chr = String.upcase(first_chr)
        remaining_str = String.slice(str, 1, str_length - 1)
        "#{first_chr}#{remaining_str}"
      else
        str
      end

    {str, first_chr}
  end

  defp step_1a(str, %{re: re, re2: re2} = opts) do
    cond do
      String.match?(str, re) ->
        {Regex.replace(re, str, "\\1\\2"), opts}

      String.match?(str, re2) ->
        {Regex.replace(re2, str, "\\1\\2"), opts}

      true ->
        {str, opts}
    end
  end

  defp re_s_v_check(str, opts) do
    opts =
      opts
      |> Map.put(:re2, @re2_1b_2)
      |> Map.put(:re3, @re3_1b_2)
      |> Map.put(:re4, @re4_1b_2)

    %{re2: re2, re3: re3, re4: re4} = opts

    cond do
      String.match?(str, re2) ->
        {"#{str}e", opts}

      String.match?(str, re3) ->
        re = @re_1b_2
        {Regex.replace(re, str, ""), %{opts | re: re}}

      String.match?(str, re4) ->
        {"#{str}e", opts}

      true ->
        {str, opts}
    end
  end

  defp step_1b(str, %{re: re, re2: re2} = opts) do
    cond do
      String.match?(str, re) ->
        matches = Regex.scan(re, str) |> hd()
        stem = Enum.at(matches, 1)
        re = @re_mgr0
        opts = %{opts | re: re}

        if String.match?(stem, re) do
          re = @re_1b_2
          opts = %{opts | re: re}

          {Regex.replace(re, str, ""), opts}
        else
          {str, opts}
        end

      String.match?(str, re2) ->
        matches = Regex.scan(re2, str) |> hd()
        stem = Enum.at(matches, 1)
        re2 = @re_s_v
        opts = %{opts | re2: re2}

        if String.match?(stem, re2) do
          re_s_v_check(stem, opts)
        else
          {str, opts}
        end

      true ->
        {str, opts}
    end
  end

  defp step_1c(str, %{re: re} = opts) do
    case String.match?(str, re) do
      true ->
        matches = Regex.scan(re, str) |> hd()
        stem = Enum.at(matches, 1)

        {"#{stem}i", opts}

      false ->
        {str, opts}
    end
  end

  defp step_2(str, %{re: re} = opts) do
    with true <- String.match?(str, re),
         matches <- Regex.scan(re, str) |> hd(),
         stem <- Enum.at(matches, 1),
         suffix <- Enum.at(matches, 2),
         %{re: re} = opts <- %{opts | re: @re_mgr0},
         true <- String.match?(stem, re) do
      {"#{stem}#{@step_2_list[suffix]}", opts}
    else
      false ->
        {str, opts}
    end
  end

  defp step_3(str, %{re: re} = opts) do
    with true <- String.match?(str, re),
         matches <- Regex.scan(re, str) |> hd(),
         stem <- Enum.at(matches, 1),
         suffix <- Enum.at(matches, 2),
         %{re: re} = opts <- %{opts | re: @re_mgr0},
         true <- String.match?(stem, re) do
      {"#{stem}#{@step_3_list[suffix]}", opts}
    else
      false ->
        {str, opts}
    end
  end

  defp step_4(str, %{re: re, re2: re2} = opts) do
    cond do
      String.match?(str, re) ->
        matches = Regex.scan(re, str) |> hd()
        stem = Enum.at(matches, 1)
        re = @re_mgr1
        opts = %{opts | re: re}

        if String.match?(stem, re) do
          {stem, opts}
        else
          {str, opts}
        end

      String.match?(str, re2) ->
        matches = Regex.scan(re2, str) |> hd()
        stem = Enum.at(matches, 1)
        suffix = Enum.at(matches, 2)
        stem = "#{stem}#{suffix}"
        re2 = @re_mgr1
        opts = %{opts | re2: re2}

        if String.match?(stem, re2) do
          {stem, opts}
        else
          {str, opts}
        end

      true ->
        {str, opts}
    end
  end

  defp step_5(str, %{re: re} = opts) do
    case String.match?(str, re) do
      false ->
        {str, opts}

      true ->
        matches = Regex.scan(re, str) |> hd()
        stem = Enum.at(matches, 1)
        re = @re_mgr1
        re2 = @re_meq1
        re3 = @re3_5

        opts =
          opts
          |> Map.put(:re, re)
          |> Map.put(:re2, re2)
          |> Map.put(:re3, re3)

        if String.match?(stem, re) || (String.match?(stem, re2) && not String.match?(stem, re3)) do
          {stem, opts}
        else
          {str, opts}
        end
    end
  end

  defp last_step(str, %{re: re, re2: re2} = opts) do
    case String.match?(str, re) && String.match?(str, re2) do
      false ->
        {str, opts}

      true ->
        re = @re_1b_2
        str = Regex.replace(re, str, "")

        {str, %{opts | re: re}}
    end
  end
end
