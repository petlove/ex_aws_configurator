defmodule ExAwsConfigurator.ConfigTest do
  use ExUnit.Case, async: true

  alias ExAwsConfigurator.Config

  describe "load!/1 + validate/1" do
    test "normalizes a minimal valid config" do
      raw = [
        queue_prefix: "billing-dev",
        topics: [%{name: :orders}],
        queues: [%{name: :orders_events, subscribe_to: [:orders]}]
      ]

      assert %Config{queues: [queue]} = Config.load!(raw)
      assert queue.name == :orders_events
      assert queue.visibility_timeout == 60
      assert queue.dlq.max_receive_count == 5
    end

    test "dlq: false disables the DLQ" do
      raw = [
        queue_prefix: "x",
        topics: [%{name: :t}],
        queues: [%{name: :q, dlq: false, subscribe_to: [:t]}]
      ]

      assert [queue] = Config.load!(raw).queues
      assert is_nil(queue.dlq)
    end

    test "dlq as map overrides defaults" do
      raw = [
        queue_prefix: "x",
        topics: [%{name: :t}],
        queues: [%{name: :q, dlq: %{max_receive_count: 10}, subscribe_to: [:t]}]
      ]

      assert [queue] = Config.load!(raw).queues
      assert queue.dlq.max_receive_count == 10
      # Other defaults preserved.
      assert queue.dlq.suffix == "_failures"
    end

    test "missing queue_prefix fails" do
      assert_raise ArgumentError, ~r/queue_prefix is required/, fn ->
        Config.load!(topics: [], queues: [])
      end
    end

    test "duplicate topic names across local + external fail" do
      raw = [
        queue_prefix: "x",
        topics: [%{name: :shared}],
        external_topics: [%{name: :shared, prefix: "other"}],
        queues: []
      ]

      assert_raise ArgumentError, ~r/duplicated/, fn -> Config.load!(raw) end
    end

    test "queue subscribing to unknown topic fails" do
      raw = [
        queue_prefix: "x",
        topics: [%{name: :a}],
        queues: [%{name: :q, subscribe_to: [:a, :missing]}]
      ]

      assert_raise ArgumentError, ~r/unknown topic.*missing/, fn -> Config.load!(raw) end
    end

    test "external topic without :arn or :prefix fails" do
      raw = [
        queue_prefix: "x",
        external_topics: [%{name: :broken}],
        queues: []
      ]

      assert_raise ArgumentError, ~r/:arn or :prefix/, fn -> Config.load!(raw) end
    end

    test "FIFO queue subscribing to non-FIFO topic fails" do
      raw = [
        queue_prefix: "x",
        topics: [%{name: :plain, fifo: false}],
        queues: [%{name: :fifo_q, fifo: true, subscribe_to: [:plain]}]
      ]

      assert_raise ArgumentError, ~r/FIFO.*non-FIFO/, fn -> Config.load!(raw) end
    end

    test "detects v1-style map shape for topics/queues" do
      raw = [
        account_id: "1234",
        environment: "prod",
        topics: %{orders: %{prefix: "billing"}},
        queues: %{events: %{topics: [:orders], attributes: [visibility_timeout: 60]}}
      ]

      err = assert_raise ArgumentError, fn -> Config.load!(raw) end
      assert err.message =~ "v1.x-style configuration"
      assert err.message =~ "`topics` is a map"
      assert err.message =~ "`queues` is a map"
      assert err.message =~ ":account_id"
      assert err.message =~ ":environment"
    end

    test "detects v1-style nested keys on queue entries" do
      raw = [
        queue_prefix: "x",
        topics: [%{name: :t}],
        queues: [
          %{name: :events, topics: [:t], attributes: [], options: [dead_letter_queue: true]}
        ]
      ]

      err = assert_raise ArgumentError, fn -> Config.load!(raw) end
      assert err.message =~ "queue entries use removed key(s)"
      assert err.message =~ ":attributes"
      assert err.message =~ ":options"
      assert err.message =~ ":topics"
    end

    test "accumulates multiple problems in one error" do
      raw = [
        topics: [%{name: :dup}, %{name: :dup}],
        queues: [%{name: :q, subscribe_to: [:missing]}, %{name: :q}]
      ]

      err = assert_raise ArgumentError, fn -> Config.load!(raw) end
      assert err.message =~ "queue_prefix is required"
      assert err.message =~ "topic name(s) duplicated"
      assert err.message =~ "queue name(s) duplicated"
      assert err.message =~ "unknown topic"
    end
  end
end
