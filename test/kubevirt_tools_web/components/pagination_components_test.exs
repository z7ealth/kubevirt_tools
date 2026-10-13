defmodule KubevirtToolsWeb.PaginationComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias KubevirtToolsWeb.PaginationComponents, as: P

  describe "paginate/2" do
    test "slices the requested page" do
      page = P.paginate(Enum.to_list(1..60), %{page: 2, per_page: 25})
      assert page.rows == Enum.to_list(26..50)
      assert %{page: 2, per_page: 25, count: 60} = page
    end

    test "clamps a page past the end to the last page" do
      page = P.paginate(Enum.to_list(1..30), %{page: 9, per_page: 25})
      assert page.page == 2
      assert page.rows == Enum.to_list(26..30)
    end

    test "an empty list is page 1 with no rows" do
      assert %{rows: [], page: 1, count: 0} = P.paginate([], %{page: 3, per_page: 10})
    end
  end

  describe "handle_pagination_event/3" do
    setup do
      %{pagination: P.new(["vms", "nodes"])}
    end

    test "set_page parses the page", %{pagination: p} do
      p = P.handle_pagination_event(p, "set_page", %{"key" => "vms", "page" => "3"})
      assert p["vms"] == %{page: 3, per_page: 25}
      assert p["nodes"] == %{page: 1, per_page: 25}
    end

    test "set_per_page goes back to page 1", %{pagination: p} do
      p = P.handle_pagination_event(p, "set_page", %{"key" => "vms", "page" => "3"})
      p = P.handle_pagination_event(p, "set_per_page", %{"key" => "vms", "rows_per_page" => "50"})
      assert p["vms"] == %{page: 1, per_page: 50}
    end

    test "ignores invalid values and unknown keys", %{pagination: p} do
      for params <- [
            %{"key" => "vms", "page" => "0"},
            %{"key" => "vms", "page" => "abc"},
            %{"key" => "nope", "page" => "2"}
          ] do
        assert P.handle_pagination_event(p, "set_page", params) == p
      end

      assert P.handle_pagination_event(p, "set_per_page", %{
               "key" => "vms",
               "rows_per_page" => "7"
             }) ==
               p
    end

    test "reset_page/2", %{pagination: p} do
      p = P.handle_pagination_event(p, "set_page", %{"key" => "vms", "page" => "4"})
      assert P.reset_page(p, "vms")["vms"].page == 1
    end
  end

  describe "table_pager/1" do
    test "renders the MD3 pager with the range" do
      html =
        render_component(&P.table_pager/1,
          id: "vms-pagination",
          key: "vms",
          page: P.paginate(Enum.to_list(1..60), %{page: 2, per_page: 25})
        )

      assert html =~ ~s(id="vms-pagination")
      assert html =~ "26–50 of 60"
    end

    test "is hidden when everything fits on the smallest page" do
      html =
        render_component(&P.table_pager/1,
          id: "vms-pagination",
          key: "vms",
          page: P.paginate(Enum.to_list(1..8), %{page: 1, per_page: 25})
        )

      refute html =~ "vms-pagination"
    end
  end
end
