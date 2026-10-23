defmodule ExAwsConfigurator.Propagator do
  @moduledoc """
  Trace context propagation for `ExAwsConfigurator.SNS.publish/3` and
  `ExAwsConfigurator.SQS.send_message/3`.

  A propagator is a module implementing `c:inject/0`: it returns the headers
  (`{name, value}` pairs) that carry the current trace context. When one is configured,
  those pairs are added as string `message_attributes` to every message published or
  sent, so the consumer can continue the trace. Attributes the caller already passed
  with the same name are kept untouched.

      config :ex_aws_configurator,
        propagator: ExAwsConfigurator.Propagator.OpenTelemetry

  `ExAwsConfigurator.Propagator.OpenTelemetry` is available when the `opentelemetry_api`
  package is in your deps. Any other tracer (Spandex, for example) works through your
  own module, or a `{module, function, args}` returning the pairs:

      config :ex_aws_configurator,
        propagator: {MyApp.Tracing, :trace_headers, []}

  Without `propagator` (the default) nothing is injected.
  """

  alias ExAwsConfigurator.Config

  @type headers :: [{String.t(), String.t()}]
  @type t :: module | {module, atom, list} | nil

  @doc "The headers that carry the current trace context."
  @callback inject() :: headers

  @doc false
  @spec inject_message_attributes(keyword, :sns | :sqs) :: keyword
  def inject_message_attributes(opts, service) do
    case headers(Config.propagator()) do
      [] ->
        opts

      headers ->
        existing = opts |> Keyword.get(:message_attributes, []) |> List.wrap()
        names = Enum.map(existing, &Map.get(&1, :name))

        injected =
          for {name, value} <- headers, name not in names, do: attribute(name, value, service)

        Keyword.put(opts, :message_attributes, existing ++ injected)
    end
  end

  @doc """
  The trace headers carried by the `message_attributes` of a received message, ready to
  be handed to the propagator (`ExAwsConfigurator.Propagator.OpenTelemetry.extract/1`).

  Accepts the map of attributes by name that `ExAws.SQS` parses (and `BroadwaySQS` puts
  in the message metadata), in the `value` or `string_value` shape, and keeps only the
  string ones. A list of `{name, value}` pairs is returned as it is.
  """
  @spec headers_from_message_attributes(map | headers) :: headers
  def headers_from_message_attributes(attributes) when is_map(attributes) do
    for {name, attribute} <- attributes,
        value = attribute_value(attribute),
        is_binary(value),
        do: {to_string(name), value}
  end

  def headers_from_message_attributes(headers) when is_list(headers), do: headers

  defp headers(nil), do: []
  defp headers({module, function, args}), do: apply(module, function, args)
  defp headers(module) when is_atom(module), do: module.inject()

  defp attribute(name, value, :sns),
    do: %{name: name, data_type: :string, value: {:string, value}}

  defp attribute(name, value, :sqs), do: %{name: name, data_type: :string, value: value}

  defp attribute_value(%{value: value}), do: value
  defp attribute_value(%{string_value: value}), do: value
  defp attribute_value(_attribute), do: nil
end

if Code.ensure_loaded?(:otel_propagator_text_map) do
  defmodule ExAwsConfigurator.Propagator.OpenTelemetry do
    @moduledoc """
    `ExAwsConfigurator.Propagator` backed by the OpenTelemetry text map propagator
    configured in the app (`traceparent`/`tracestate` with the default W3C one).
    Available when the `opentelemetry_api` package is in your deps.

    On the consumer side, `extract/1` continues the trace from the attributes of a
    received message. In a Broadway SQS pipeline, ask the producer for them with
    `message_attribute_names: header_names()` and wrap the processing in a span,
    detaching the context afterwards so the next message does not inherit it:

        def handle_message(_processor, message, _context) do
          token = Propagator.OpenTelemetry.extract(message.metadata.message_attributes)

          try do
            OpenTelemetry.Tracer.with_span "orders.process", %{kind: :consumer} do
              process(message)
            end
          after
            OpenTelemetry.Ctx.detach(token)
          end
        end
    """

    @behaviour ExAwsConfigurator.Propagator

    alias ExAwsConfigurator.Propagator

    @header_names ["traceparent", "tracestate"]

    @doc """
    Names of the message attributes that carry the trace context, for the
    `message_attribute_names` option of the SQS producer.
    """
    @spec header_names() :: [String.t()]
    def header_names, do: @header_names

    @impl true
    def inject, do: :otel_propagator_text_map.inject([])

    @doc """
    Extract the trace context from the `message_attributes` of a received message (see
    `ExAwsConfigurator.Propagator.headers_from_message_attributes/1`) and attach it to
    the current process. Returns the token to hand to `OpenTelemetry.Ctx.detach/1`.
    """
    @spec extract(map | Propagator.headers()) :: :otel_ctx.token()
    def extract(attributes) do
      attributes
      |> Propagator.headers_from_message_attributes()
      |> :otel_propagator_text_map.extract()
    end
  end
end
