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
    output = Keyword.get(opts, :output, "coverage.xml")

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

    root = {:coverage, [
        timestamp: timestamp(),
        'line-rate': 0,
        'lines-covered': 0,
        'lines-valid': 0,
        'branch-rate': 0,
        'branches-covered': 0,
        'branches-valid': 0,
        complexity: 0,
        version: "1.9",
      ], [
        sources: [],
        packages: packages,
      ]
    }
    report = :xmerl.export_simple([root], :xmerl_xml, prolog: prolog)
    :ok = File.write(output, report)
  end

  defp packages do
    [{:package, [name: "", 'line-rate': 0, 'branch-rate': 0, complexity: 1], [
      classes: Enum.map(:cover.modules, fn mod ->
        class_name = inspect(mod)
        # <class branch-rate="0.634920634921" complexity="0.0"
        #  filename="PSPDFKit/PSPDFConfiguration.m" line-rate="0.976377952756"
        #  name="PSPDFConfiguration_m">

        {:class,
          [
            name: inspect(mod),
            filename: Path.relative_to_cwd(mod.module_info(:compile)[:source]),
            'line-rate': 0, 'branch-rate': 0, complexity: 1,
          ],
          [methods: methods(mod), lines: lines(mod)]
        }
      end)
    ]}]
  end

  defp methods(mod) do
    {:ok, functions} = :cover.analyse(mod, :calls, :function)

    functions
    |> Stream.map(&elem(&1, 0))
    |> Stream.map(fn {_m, f, a} ->
      # <method name="main" signature="([Ljava/lang/String;)V" line-rate="1.0" branch-rate="1.0">
      {:method, [name: to_string(f), signature: "", 'line-rate': 0, 'branch-rate': 0], []}
    end)
    |> Enum.to_list
  end

  defp lines(mod) do
    {:ok, lines} = :cover.analyse(mod, :calls, :line)

    lines
    |> Stream.filter(fn {{_m, line}, _hits} -> line != 0 end)
    |> Enum.map(fn {{_m, line}, hits} ->
      # <line branch="false" hits="21" number="76"/>
      {:line, [branch: false, hits: hits, number: line], []}
    end)
  end

  defp timestamp do
    {mega, seconds, micro} = :os.timestamp()
    mega * 1000000000 + seconds * 1000 + div(micro, 1000)
  end
end
