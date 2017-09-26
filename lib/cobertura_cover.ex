defmodule CoberturaCover do
  def start(compile_path, opts) do
    Mix.shell.info "Cover compiling modules ... "
    _ = :cover.start

    case :cover.compile_beam_directory(compile_path |> to_char_list) do
      results when is_list(results) ->
        :ok
      {:error, _} ->
        Mix.raise "Failed to cover compile directory: " <> compile_path
    end

    html_output = opts[:html_output]
    output = Keyword.get(opts, :xml_output, "coverage.xml")

    fn() ->
      generate_cobertura(output)
      if html_output, do: generate_html(html_output)
    end
  end

  def generate_html(output) do
    File.mkdir_p!(output)
    Mix.shell.info "\nGenerating cover HTML output..."
    Enum.each :cover.modules, fn(mod) ->
      {:ok, _} = :cover.analyse_to_file(mod, '#{output}/#{mod}.html', [:html])
    end
  end

  def generate_cobertura(output) do
    Mix.shell.info "\nGenerating #{output}... "

    prolog = [
      ~s(<?xml version="1.0" encoding="utf-8"?>\n),
      ~s(<!DOCTYPE coverage SYSTEM "http://cobertura.sourceforge.net/xml/coverage-04.dtd">\n)
    ]

    {coverage, tree} = packages()
    root = {:coverage, [
        timestamp: timestamp(),
        'line-rate': coverage |> cover_ratio |> to_string,
        'lines-covered': 0,
        'lines-valid': 0,
        'branch-rate': 0,
        'branches-covered': 0,
        'branches-valid': 0,
        complexity: 0,
        version: "1.9",
      ], [
        sources: [],
        packages: tree,
      ]
    }
    report = :xmerl.export_simple([root], :xmerl_xml, prolog: prolog)
    :ok = File.write(output, report)
  end

  defp packages do
    {coverage, tree} = classes()
    tree =
      [
        {
          :package,
          [
            name: "",
            'line-rate': coverage |> cover_ratio |> to_string,
            'branch-rate': 0,
            complexity: 1
          ],
          [classes: tree]
        }
      ]
    {coverage, tree}
  end

  defp classes do
    modules = :cover.modules
    reduce_analysis(modules, &class/1)
  end

  defp class(module) do
    module_name = inspect(module)
    file_name = Path.relative_to_cwd(module.module_info(:compile)[:source])
    {methods_coverage, methods_tree} = methods(module)
    {_hits, lines_tree} = lines(module)
    tree =
      {:class,
        [
          name: module_name,
          filename: file_name,
          'line-rate': methods_coverage |> cover_ratio |> to_string,
          'branch-rate': 0,
          complexity: 1,
        ],
        [
          methods: methods_tree,
          lines: lines_tree
        ]
      }
    {methods_coverage, tree}
  end

  defp methods(module) do
    {:ok, functions} = :cover.analyse(module, :coverage, :function)
    reduce_analysis(functions, &method/1)
  end

  defp method({{_module, :__info__, _arity}, _coverage}), do: nil
  defp method({{_module, name, arity}, coverage}) do
    tree =
      {
        :method,
        [
          name: "#{name}/#{arity}",
          signature: "",
          'line-rate': coverage |> cover_ratio |> to_string,
          'branch-rate': 0
        ],
        []
      }
    {coverage, tree}
  end

  defp lines(module) do
    {:ok, lines} = :cover.analyse(module, :calls, :line)
    reduce_analysis(lines, &line/1)
  end

  defp line({{_module, 0}, _hits}), do: nil
  defp line({{_module, line_number}, hits}) do
    tree =
      {
        :line,
        [
          branch: false,
          hits: hits,
          number: line_number
        ],
        []
      }
    {hits, tree}
  end


  defp reduce_analysis(targets, processor) do
    {acc, collection} =
      Enum.reduce(
        targets,
        {nil, []},
        fn (target, acc) ->
          case processor.(target) do
            nil -> acc
            {new_val, tree} -> accumulate(acc, {new_val, tree})
          end
        end
      )
    {acc, Enum.reverse(collection)}
  end

  defp accumulate({nil, collection}, {new_val, tree}) when is_integer(new_val), do: {new_val, [tree | collection]}
  defp accumulate({acc, collection}, {new_val, tree}) when is_integer(new_val), do: {acc + new_val, [tree | collection]}
  defp accumulate({nil, collection}, {{_covered, _not_covered} = new_val, tree}), do: {new_val, [tree | collection]}
  defp accumulate({{old_covered, old_not_covered}, collection}, {{covered, not_covered}, tree}) do
    {{old_covered + covered, old_not_covered + not_covered}, [tree | collection]}
  end

  defp timestamp do
    {mega, seconds, micro} = :os.timestamp()
    mega * 1000000000 + seconds * 1000 + div(micro, 1000)
  end

  defp cover_ratio({0, 0}), do: 0
  defp cover_ratio({covered, not_covered}), do: covered / (covered + not_covered)
end
