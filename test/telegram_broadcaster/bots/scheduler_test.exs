defmodule TelegramBroadcaster.SchedulerTest do
  use ExUnit.Case, async: true

  alias TelegramBroadcaster.Scheduler

  describe "next_action/1 — delete priority" do
    test "returns delete before insert when both queues exist" do
      tracked = %{
        "order:1" => %{
          insert_queue: [{"111", "Hello", %{}}],
          delete_queue: [{"222", 47852}],
          in_flight: 0
        }
      }

      assert {:delete, "order:1", {"222", 47852}} = Scheduler.next_action(tracked)
    end
  end

  describe "next_action/1 — insert only" do
    test "returns send when only insert_queue has items" do
      tracked = %{
        "order:1" => %{
          insert_queue: [{"111", "Hello", %{}}],
          delete_queue: [],
          in_flight: 0
        }
      }

      assert {:send, "order:1", {"111", "Hello", %{}}} = Scheduler.next_action(tracked)
    end
  end

  describe "next_action/1 — empty" do
    test "returns :empty when all queues are empty" do
      tracked = %{
        "order:1" => %{
          insert_queue: [],
          delete_queue: [],
          in_flight: 0
        }
      }

      assert :empty = Scheduler.next_action(tracked)
    end

    test "returns :empty when tracked map is empty" do
      assert :empty = Scheduler.next_action(%{})
    end
  end

  describe "next_action/1 — multiple tracking_ids" do
    test "picks from first tracking_id with pending work" do
      tracked = %{
        "order:1" => %{
          insert_queue: [],
          delete_queue: [],
          in_flight: 0
        },
        "order:2" => %{
          insert_queue: [{"333", "New order", %{}}],
          delete_queue: [],
          in_flight: 0
        }
      }

      assert {:send, "order:2", {"333", "New order", %{}}} = Scheduler.next_action(tracked)
    end
  end
end
