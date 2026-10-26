defmodule ExAwsConfigurator.PropagatorTest do
  # Changes the `propagator` application env and the global OpenTelemetry propagator.
  use ExAwsConfigurator.Case, async: false

  alias ExAwsConfigurator.{Propagator, SNS, SQS}
  alias ExAwsConfigurator.Propagator.OpenTelemetry, as: OTelPropagator

  @moduletag capture_log: true

  @trace_id 0x4BF92F3577B34DA6A3CE929D0E0E4736
  @span_id 0x00F067AA0BA902B7
  @traceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

  def headers, do: [{"traceparent", @traceparent}, {"x-custom", "value"}]

  defmodule Stub do
    @behaviour ExAwsConfigurator.Propagator

    @impl true
    def inject, do: [{"traceparent", "00-stub"}]
  end

  defp configure(propagator) do
    Application.put_env(:ex_aws_configurator, :propagator, propagator)
    on_exit(fn -> Application.delete_env(:ex_aws_configurator, :propagator) end)
  end

  describe "inject_message_attributes/2" do
    test "leaves the opts untouched without a propagator" do
      assert Propagator.inject_message_attributes([message_group_id: "g"], :sns) == [
               message_group_id: "g"
             ]
    end

    test "adds the headers of a {module, function, args} as sns string attributes" do
      configure({__MODULE__, :headers, []})

      opts = Propagator.inject_message_attributes([message_group_id: "g"], :sns)

      assert opts[:message_group_id] == "g"

      assert opts[:message_attributes] == [
               %{name: "traceparent", data_type: :string, value: {:string, @traceparent}},
               %{name: "x-custom", data_type: :string, value: {:string, "value"}}
             ]
    end

    test "adds the headers of a module as sqs string attributes" do
      configure(Stub)

      assert Propagator.inject_message_attributes([], :sqs) == [
               message_attributes: [%{name: "traceparent", data_type: :string, value: "00-stub"}]
             ]
    end

    test "keeps the attributes given by the caller, including one with the same name" do
      configure(Stub)
      mine = %{name: "traceparent", data_type: :string, value: {:string, "00-mine"}}

      assert Propagator.inject_message_attributes([message_attributes: mine], :sns) == [
               message_attributes: [mine]
             ]

      other = %{name: "other", data_type: :number, value: {:string, "1"}}

      assert [message_attributes: [^other, %{name: "traceparent"}]] =
               Propagator.inject_message_attributes([message_attributes: [other]], :sns)
    end
  end

  describe "headers_from_message_attributes/1" do
    test "reads the value or string_value of string attributes" do
      attributes = %{
        "traceparent" => %{name: "traceparent", data_type: "String", string_value: "00-a"},
        "tracestate" => %{value: "vendor=1"},
        "count" => %{name: "count", data_type: "Number", string_value: "1"},
        "blob" => %{name: "blob", data_type: "Binary", string_value: nil, binary_value: "x"},
        "raw" => %{binary_value: "x"}
      }

      assert Propagator.headers_from_message_attributes(attributes) |> Enum.sort() == [
               {"count", "1"},
               {"traceparent", "00-a"},
               {"tracestate", "vendor=1"}
             ]
    end

    test "returns pairs as they are" do
      assert Propagator.headers_from_message_attributes([{"traceparent", "00-a"}]) == [
               {"traceparent", "00-a"}
             ]
    end
  end

  describe "OpenTelemetry" do
    setup do
      :opentelemetry.set_text_map_propagator(:otel_propagator_trace_context)
      on_exit(fn -> :opentelemetry.set_text_map_propagator(:otel_propagator_text_map_noop) end)
    end

    test "inject returns the traceparent of the current span" do
      @trace_id
      |> :otel_tracer.non_recording_span(@span_id, 1)
      |> :otel_tracer.set_current_span()

      assert OTelPropagator.inject() == [{"traceparent", @traceparent}]
      assert OTelPropagator.header_names() == ["traceparent", "tracestate"]
    end

    test "inject returns nothing without a current span" do
      assert OTelPropagator.inject() == []
    end

    test "extract continues the trace from the message attributes" do
      attributes = %{"traceparent" => %{data_type: "String", string_value: @traceparent}}

      token = OTelPropagator.extract(attributes)
      span_ctx = :otel_tracer.current_span_ctx()

      assert :otel_span.trace_id(span_ctx) == @trace_id
      assert :otel_span.span_id(span_ctx) == @span_id

      :otel_ctx.detach(token)
      assert :otel_tracer.current_span_ctx() == :undefined
    end
  end

  describe "publishing with a propagator" do
    setup do
      configure({__MODULE__, :headers, []})
    end

    test "SNS.publish/3 sends the trace headers as message attributes" do
      topic = build(:topic)
      {:ok, _} = SNS.create_topic(topic)

      assert {:ok, %{status_code: 200}} = SNS.publish(topic, %{event: "created"})
    end

    test "SQS.send_message/3 delivers the trace headers as message attributes" do
      queue = build(:queue)
      {:ok, _} = SQS.create_queue(queue)

      assert {:ok, %{status_code: 200}} = SQS.send_message(queue, "message")

      assert {:ok, %{body: %{messages: [message]}}} =
               queue
               |> ExAwsConfigurator.Queue.url()
               |> ExAws.SQS.receive_message(message_attribute_names: ["traceparent", "x-custom"])
               |> ExAws.request(region: queue.region)

      assert Propagator.headers_from_message_attributes(message.message_attributes)
             |> Enum.sort() == Enum.sort(headers())
    end
  end
end
