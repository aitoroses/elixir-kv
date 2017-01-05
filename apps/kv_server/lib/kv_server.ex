defmodule KVServer do
  use Application
  require Logger

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    {:ok, port} = Application.fetch_env(:kv_server, :port)

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(Task.Supervisor, [[name: KVServer.TaskSupervisor]]),
      worker(Task, [KVServer, :accept, [port]]),
    ]

    opts = [strategy: :one_for_one, name: KVServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def accept(port) do
    # The options below mean:
    #
    # 1. `:binary` - receives data as binaries (instead of lists)
    # 2. `packet: :line` - receives data line by line
    # 3. `active: false` - blocks on `:gen_tcp.recv/2` until data is available
    # 4. `reuseaddr: true` - allows us to reuse the address if the listener crashes
    #
    msg = :gen_tcp.listen(port,
                      [:binary, packet: :line, active: false, reuseaddr: true])
    case msg do
        {:ok, socket} ->
            Logger.info "Accepting connections on port #{port}"
            loop_acceptor(socket)

        {:error, :eaddrinuse} = err ->
            #Logger.info "Node skipped listening."
            err
    end
  end

    defp loop_acceptor(socket) do
        {:ok, client} = :gen_tcp.accept(socket)
        {:ok, pid} = Task.Supervisor.start_child(KVServer.TaskSupervisor,
            fn -> serve(client) end)
        :ok = :gen_tcp.controlling_process(client, pid)
        loop_acceptor(socket)
    end

    defp serve(socket) do
        msg =
            with {:ok, data} <- read_line(socket),
                 {:ok, command} <- KVServer.Command.parse(data),
                 do: KVServer.Command.run(command)

        write_line(socket, msg)
        serve(socket)
    end

    defp read_line(socket) do
        :gen_tcp.recv(socket, 0)
    end

    defp write_line(socket, {:ok, text}) do
        :gen_tcp.send(socket, text)
    end

    defp write_line(socket, {:error, :unknown_command}) do
        :gen_tcp.send(socket, "UNKNOWN COMMAND\r\n")
    end

    defp write_line(_socket, {:error, :closed}) do
        # The connection was closed, exit politely.
        exit(:shutdown)
    end

    defp write_line(socket, {:error, :not_found}) do
        :gen_tcp.send(socket, "NOT FOUND\r\n")
    end

    defp write_line(socket, {:error, error}) do
        :gen_tcp.send(socket, "ERROR\r\n")
        exit(error)
    end

end
