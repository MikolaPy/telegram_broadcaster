defmodule TelegramBroadcaster.TelegramClient do
  @base_url "https://api.telegram.org"

  @spec send_message(String.t(), String.t(), String.t(), map() | nil) ::
          {:ok, integer()} | {:error, term()}
  def send_message(token, chat_id, text, reply_markup \\ nil) do
    url = build_send_url(token)

    body =
      %{"chat_id" => chat_id, "text" => text}
      |> maybe_add_reply_markup(reply_markup)

    case Finch.build(:post, url, [{"content-type", "application/json"}], Jason.encode!(body))
         |> Finch.request(TelegramBroadcaster.Finch) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        {:ok, decoded} = Jason.decode(resp_body)
        parse_send_response(decoded)

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:ok, decoded} = Jason.decode(resp_body)
        {:error, "HTTP #{status}: #{decoded["description"]}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec delete_message(String.t(), String.t(), integer()) ::
          :ok | {:error, term()}
  def delete_message(token, chat_id, message_id) do
    url = build_delete_url(token)

    body = %{"chat_id" => chat_id, "message_id" => message_id}

    case Finch.build(:post, url, [{"content-type", "application/json"}], Jason.encode!(body))
         |> Finch.request(TelegramBroadcaster.Finch) do
      {:ok, %Finch.Response{status: 200}} ->
        :ok

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:ok, decoded} = Jason.decode(resp_body)
        {:error, "HTTP #{status}: #{decoded["description"]}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec parse_send_response(map()) :: {:ok, integer()} | {:error, String.t()}
  def parse_send_response(%{"ok" => true, "result" => %{"message_id" => msg_id}}) do
    {:ok, msg_id}
  end

  def parse_send_response(%{"ok" => false, "description" => description}) do
    {:error, description}
  end

  def build_send_url(token), do: "#{@base_url}/bot#{token}/sendMessage"
  def build_delete_url(token), do: "#{@base_url}/bot#{token}/deleteMessage"

  defp maybe_add_reply_markup(body, nil), do: body
  defp maybe_add_reply_markup(body, markup), do: Map.put(body, "reply_markup", markup)
end
