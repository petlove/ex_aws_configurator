defmodule ExAwsConfigurator.HttpStub do
  @moduledoc """
  ExAws http client used by the test suite. It forwards every request to the local
  SQS/SNS backend (floci) and simulates only what that backend cannot:

    * AWS name validation: `CreateQueue`/`CreateTopic` with an invalid name get a 400, and
      looking such a resource up (`GetQueueUrl`/`GetTopicAttributes`) says it does not exist,
      even if a previous run left it behind in the local backend;
    * an external account that refuses `sns:Subscribe`: subscribing to a topic owned by
      `external_account_id/0` gets a 403 `AuthorizationError`;
    * any other failure: after `fail/1`, the given actions get a 403 `AccessDenied` in the
      calling process (ExAws runs the http client in the caller, so async tests are safe).
  """

  @behaviour ExAws.Request.HttpClient

  alias ExAws.Request.Hackney

  @external_account_id "829683656197"
  @valid_name ~r/\A[A-Za-z0-9_-]+(\.fifo)?\z/

  def external_account_id, do: @external_account_id

  @doc "Make every `action` (`\"GetQueueUrl\"`, ...) requested by the calling process fail."
  def fail(action), do: Process.put({__MODULE__, :failures}, [action | failures()])

  defp failures, do: Process.get({__MODULE__, :failures}, [])

  @impl true
  def request(method, url, body, headers, http_opts) do
    params = URI.decode_query(body)

    cond do
      params["Action"] in failures() ->
        {:ok, %{status_code: 403, headers: [], body: access_denied_error(params)}}

      invalid_name?(params) ->
        {:ok, %{status_code: 400, headers: [], body: invalid_name_error(params)}}

      missing_by_invalid_name?(params) ->
        {:ok,
         %{status_code: not_found_status(params), headers: [], body: not_found_error(params)}}

      subscribe_to_external_topic?(params) ->
        {:ok, %{status_code: 403, headers: [], body: authorization_error()}}

      true ->
        Hackney.request(method, url, body, headers, http_opts)
    end
  end

  defp invalid_name?(%{"Action" => "CreateQueue", "QueueName" => name}),
    do: not Regex.match?(@valid_name, name)

  defp invalid_name?(%{"Action" => "CreateTopic", "Name" => name}),
    do: not Regex.match?(@valid_name, name)

  defp invalid_name?(_), do: false

  defp missing_by_invalid_name?(%{"Action" => "GetQueueUrl", "QueueName" => name}),
    do: not Regex.match?(@valid_name, name)

  defp missing_by_invalid_name?(%{"Action" => "GetTopicAttributes", "TopicArn" => arn}),
    do: not Regex.match?(@valid_name, arn |> String.split(":") |> List.last())

  defp missing_by_invalid_name?(_), do: false

  defp subscribe_to_external_topic?(%{"Action" => "Subscribe", "TopicArn" => arn}),
    do: String.contains?(arn, @external_account_id)

  defp subscribe_to_external_topic?(_), do: false

  defp invalid_name_error(%{"Action" => "CreateQueue"}),
    do:
      error_response(
        "InvalidParameterValue",
        "Can only include alphanumeric characters, hyphens, or underscores. 1 to 80 in length"
      )

  defp invalid_name_error(%{"Action" => "CreateTopic"}),
    do: error_response("InvalidParameter", "Invalid parameter: Topic Name")

  # SQS answers 400 for a missing queue, SNS answers 404 for a missing topic.
  defp not_found_status(%{"Action" => "GetQueueUrl"}), do: 400
  defp not_found_status(%{"Action" => "GetTopicAttributes"}), do: 404

  defp not_found_error(%{"Action" => "GetQueueUrl"}),
    do:
      error_response(
        "AWS.SimpleQueueService.NonExistentQueue",
        "The specified queue does not exist."
      )

  defp not_found_error(%{"Action" => "GetTopicAttributes"}),
    do: error_response("NotFound", "Topic does not exist")

  defp authorization_error do
    error_response(
      "AuthorizationError",
      "User: arn:aws:iam::000000000000:user/app is not authorized to perform: " <>
        "SNS:Subscribe on resource: arn:aws:sns:sa-east-1:#{@external_account_id}:topic"
    )
  end

  defp access_denied_error(%{"Action" => action}),
    do: error_response("AccessDenied", "Not authorized to perform: #{action}")

  defp error_response(code, message) do
    """
    <ErrorResponse xmlns="http://queue.amazonaws.com/doc/2012-11-05/">
      <Error>
        <Type>Sender</Type>
        <Code>#{code}</Code>
        <Message>#{message}</Message>
      </Error>
      <RequestId>00000000-0000-0000-0000-000000000000</RequestId>
    </ErrorResponse>
    """
  end
end
