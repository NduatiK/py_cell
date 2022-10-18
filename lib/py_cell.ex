defmodule PyCell do
  @moduledoc false

  use Kino.JS
  use Kino.JS.Live
  use Kino.SmartCell, name: "Python"

  @impl true
  def init(attrs, ctx) do
    ctx =
      assign(ctx,
        function_name: attrs["function_name"] || "add"
      )

    {:ok, ctx,
     editor: [
       attribute: "python_code",
       language: "python",
       default_source:
         attrs["default_source"] ||
           """
           def add(a, b):
             return a + b
           """
     ]}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok,
     %{
       function_name: ctx.assigns.function_name
     }, ctx}
  end

  @impl true
  def handle_event("update_" <> variable_name, variable, ctx) do
    ctx = assign(ctx, [{String.to_existing_atom(variable_name), variable}])

    broadcast_event(
      ctx,
      "update_" <> variable_name,
      ctx.assigns[String.to_existing_atom(variable_name)]
    )

    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "function_name" => ctx.assigns.function_name
    }
  end

  @impl true
  def to_source(attrs) do
    quote do
      require PyCell
      PyCell.open_port(unquote(attrs["function_name"]), unquote(attrs["python_code"]))
    end
    |> Kino.SmartCell.quoted_to_string()
  end

  def open_port(function_name, python_code) do
    python = PyCell.load(function_name, python_code)

    :persistent_term.get({__MODULE__, :open_ports}, %{})
    |> then(fn existing_ports ->
      existing = Map.get(existing_ports, function_name)

      if existing != nil and Port.info(existing) != nil do
        Port.close(existing)
      end

      port =
        Port.open(
          {:spawn,
           """
           python3 -c '#{python}'
           """
           |> String.trim()},
          [:binary, :nouse_stdio, {:packet, 4}]
        )

      :persistent_term.put(
        {__MODULE__, :open_ports},
        existing_ports
        |> Map.put(function_name, port)
      )

      port
    end)

    IO.puts(
      """
      Run the \"#{function_name}\" function by running:

      PyCell.run(\"#{function_name}\", <args>)
      """
      |> String.trim()
    )
  end

  @doc """
  Run your registered function with some arguments.

  The result or an `:error` is returned.

  You can optionally provide a timeout parameter that
  kills the function execution and kills the underlying
  port if execution takes too long.
  """
  defmacro run(function_name, args, timeout \\ :infinity) do
    quote do
      open_ports = :persistent_term.get({unquote(__MODULE__), :open_ports}, %{})

      case Map.get(open_ports, unquote(function_name)) do
        nil ->
          :error

        port ->
          Port.command(port, [unquote(args) |> Jason.encode!(), "\n"])

          receive do
            {^port, {:data, "\":error\""}} ->
              :error

            {^port, {:data, result}} ->
              String.trim(result)
              |> Jason.decode!()
          after
            unquote(timeout) ->
              Port.close(port)
              IO.puts(:stderr, "No message in #{unquote(timeout)} milliseconds")
              :timeout
          end
      end
    end
  end

  def open() do
    :persistent_term.get({unquote(__MODULE__), :open_ports}, %{})
  end

  def load(function_name, python) do
    """
    import json
    import sys
    import os
    from struct import unpack, pack

    def setup_io():
        return os.fdopen(3,"rb"), os.fdopen(4,"wb")


    def read_message(input_f):
        # reading the first 4 bytes with the length of the data
        # the other 16 bytes are the UUID bytes
        # the rest is the image

        header = input_f.read(4)
        if len(header) != 4:
            return None  # EOF
        # print("header", header)

        (total_msg_size,) = unpack("!I", header)

        line = input_f.read(total_msg_size)
        # print(line)

        return json.loads(line)


    def write_result(output, result):
        result = json.dumps(result).encode("ascii")

        total_msg_size = len(result)

        header = pack("!I", total_msg_size)
        output.write(header)
        output.write(result)
        output.flush()

    #{python}

    input_f, output_f = setup_io()
    while True:
        msg = read_message(input_f)
        if msg is None: break
        try:
          result = #{function_name}(*msg)
          write_result(output_f, result)
        except Exception as err:
          sys.stderr.write(f"PyCell Error: {err}\\n")
          write_result(output_f, ":error")

    """
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css");
      ctx.importCSS("https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap");

      root.innerHTML = `
        <div class="app">
          <label class="label">Function Name</label>
          <input class="input" type="text" name="function_name" />
        </div>
      `;

      const sync = (id) => {
          const variableEl = ctx.root.querySelector(`[name="${id}"]`);
          variableEl.value = payload[id];

          variableEl.addEventListener("change", (event) => {
            ctx.pushEvent(`update_${id}`, event.target.value);
          });

          ctx.handleEvent(`update_${id}`, (variable) => {
            variableEl.value = variable;
          });
      }

      sync("function_name")

      ctx.handleSync(() => {
          // Synchronously invokes change listeners
          document.activeElement &&
            document.activeElement.dispatchEvent(new Event("change"));
      });
    }
    """
  end

  asset "main.css" do
    """
    .app {
      font-family: "Inter";
      display: flex;
      align-items: center;
      gap: 16px;
      background-color: #ecf0ff;
      padding: 8px 16px;
      border: solid 1px #cad5e0;
      border-radius: 0.5rem 0.5rem 0 0;
    }

    .label {
      font-size: 0.875rem;
      font-weight: 500;
      color: #445668;
      text-transform: uppercase;
    }

    .input {
      padding: 8px 12px;
      background-color: #f8f8afc;
      font-size: 0.875rem;
      border: 1px solid #e1e8f0;
      border-radius: 0.5rem;
      color: #445668;
      min-width: 150px;
    }

    .input:focus {
      border: 1px solid #61758a;
      outline: none;
    }
    """
  end
end
