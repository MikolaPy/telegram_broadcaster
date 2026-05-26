defmodule TelegramBroadcaster.DiffEngineTest do
  use ExUnit.Case, async: true

  alias TelegramBroadcaster.DiffEngine

  describe "compute/2 — new messages" do
    test "returns to_insert for chat_ids in desired but not in delivered" do
      desired = %{
        "111" => %{"text" => "Hello", "version" => 1, "reply_markup" => %{}},
        "222" => %{"text" => "Hello", "version" => 1, "reply_markup" => %{}}
      }

      delivered = %{}

      {to_insert, to_delete} = DiffEngine.compute(desired, delivered)

      assert length(to_insert) == 2
      assert to_delete == []
    end
  end

  describe "compute/2 — remove messages" do
    test "returns to_delete for chat_ids in delivered but not in desired" do
      desired = %{}

      delivered = %{
        "111" => %{"msg_id" => 47852, "version" => 1},
        "222" => %{"msg_id" => 47853, "version" => 1}
      }

      {to_insert, to_delete} = DiffEngine.compute(desired, delivered)

      assert to_insert == []
      assert length(to_delete) == 2

      chat_ids = Enum.map(to_delete, fn {chat_id, _msg_id} -> chat_id end)
      assert "111" in chat_ids
      assert "222" in chat_ids
    end
  end

  describe "compute/2 — version changed (update)" do
    test "returns both to_insert and to_delete when version differs" do
      desired = %{
        "111" => %{"text" => "6000₽", "version" => 2, "reply_markup" => %{}}
      }

      delivered = %{
        "111" => %{"msg_id" => 47852, "version" => 1}
      }

      {to_insert, to_delete} = DiffEngine.compute(desired, delivered)

      assert length(to_insert) == 1
      assert length(to_delete) == 1

      {chat_id_ins, _payload} = hd(to_insert)
      assert chat_id_ins == "111"

      {chat_id_del, msg_id} = hd(to_delete)
      assert chat_id_del == "111"
      assert msg_id == 47852
    end
  end

  describe "compute/2 — idempotent (no changes)" do
    test "returns empty lists when desired matches delivered" do
      desired = %{
        "111" => %{"text" => "Hello", "version" => 1, "reply_markup" => %{}}
      }

      delivered = %{
        "111" => %{"msg_id" => 47852, "version" => 1}
      }

      {to_insert, to_delete} = DiffEngine.compute(desired, delivered)

      assert to_insert == []
      assert to_delete == []
    end
  end

  describe "compute/2 — mixed scenario" do
    test "new + updated + removed simultaneously" do
      desired = %{
        "111" => %{"text" => "Updated", "version" => 2, "reply_markup" => %{}},
        "333" => %{"text" => "New", "version" => 1, "reply_markup" => %{}}
      }

      delivered = %{
        "111" => %{"msg_id" => 100, "version" => 1},
        "222" => %{"msg_id" => 200, "version" => 1}
      }

      {to_insert, to_delete} = DiffEngine.compute(desired, delivered)

      assert length(to_insert) == 2
      assert length(to_delete) == 2

      insert_ids = Enum.map(to_insert, fn {chat_id, _} -> chat_id end) |> Enum.sort()
      assert insert_ids == ["111", "333"]

      delete_ids = Enum.map(to_delete, fn {chat_id, _} -> chat_id end) |> Enum.sort()
      assert delete_ids == ["111", "222"]
    end
  end
end
