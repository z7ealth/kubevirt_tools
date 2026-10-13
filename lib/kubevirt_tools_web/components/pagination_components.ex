defmodule KubevirtToolsWeb.PaginationComponents do
  @moduledoc """
  Client-facing pagination for in-memory tables.

  The cluster lists are fetched whole (the overview, charts, filters and sort
  all need every item), so pagination here limits what each render sends to
  the browser, not what is fetched from the Kubernetes API.

  A LiveView keeps a `:pagination` assign, a map of table key to
  `%{page: _, per_page: _}` (see `new/1`), and forwards the pager's events to
  `handle_pagination_event/3`:

      def handle_event(event, params, socket) when event in ~w(set_page set_per_page) do
        {:noreply, update(socket, :pagination, &handle_pagination_event(&1, event, params))}
      end

  Tables call `paginate/2` after filtering and sorting, render `page.rows`,
  and put `<.table_pager>` under the table.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import PhoenixPaper.TablePagination, only: [pp_table_pagination: 1]

  @per_page_options [10, 25, 50, 100]
  @default_per_page 25

  @doc "Initial pagination state for the given table keys."
  def new(keys) do
    Map.new(keys, &{&1, %{page: 1, per_page: @default_per_page}})
  end

  @doc "Back to page 1 for `key` (after its filters or sort change)."
  def reset_page(pagination, key) do
    Map.update(pagination, key, %{page: 1, per_page: @default_per_page}, &%{&1 | page: 1})
  end

  @doc """
  Applies a `set_page` / `set_per_page` event from `table_pager/1`. Values
  come from the client, so they are parsed and anything invalid is ignored.
  """
  def handle_pagination_event(pagination, "set_page", %{"key" => key, "page" => page}) do
    case parse_positive(page) do
      nil -> pagination
      page -> update_key(pagination, key, &%{&1 | page: page})
    end
  end

  def handle_pagination_event(pagination, "set_per_page", %{"key" => key, "rows_per_page" => n}) do
    case parse_positive(n) do
      n when n in @per_page_options -> update_key(pagination, key, &%{&1 | per_page: n, page: 1})
      _ -> pagination
    end
  end

  def handle_pagination_event(pagination, _event, _params), do: pagination

  defp update_key(pagination, key, fun) do
    if Map.has_key?(pagination, key), do: Map.update!(pagination, key, fun), else: pagination
  end

  defp parse_positive(value) when is_integer(value) and value > 0, do: value

  defp parse_positive(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_positive(_), do: nil

  @doc """
  Slices `rows` to the requested page. The page is clamped to the last one,
  so a refresh or filter that shrinks the list never leaves an empty page.

  Returns `%{rows: page_rows, page: page, per_page: per_page, count: total}`.
  """
  def paginate(rows, %{page: page, per_page: per_page}) do
    count = length(rows)
    last_page = max(div(count + per_page - 1, per_page), 1)
    page = page |> max(1) |> min(last_page)

    %{
      rows: Enum.slice(rows, (page - 1) * per_page, per_page),
      page: page,
      per_page: per_page,
      count: count
    }
  end

  @doc """
  MD3 table pagination bar for a `paginate/2` result. Hidden when every row
  fits on the smallest page size.
  """
  attr :id, :string, required: true
  attr :key, :string, required: true, doc: "the table key in the :pagination assign"
  attr :page, :map, required: true, doc: "the paginate/2 result"

  def table_pager(assigns) do
    assigns = assign(assigns, :options, @per_page_options)

    ~H"""
    <.pp_table_pagination
      :if={@page.count > hd(@options)}
      id={@id}
      page={@page.page}
      count={@page.count}
      rows_per_page={@page.per_page}
      rows_per_page_options={@options}
      on_page_change={JS.push("set_page", value: %{key: @key})}
      on_rows_per_page_change={
        JS.push("set_per_page", value: %{key: @key})
        |> PhoenixPaper.Menu.close("#{@id}-rows-per-page")
      }
      class="border-t border-pp-outline-variant"
    />
    """
  end
end
