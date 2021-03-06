defmodule Plug.ParsersTest do
  use ExUnit.Case, async: true

  import Plug.Test

  def parse(conn, opts \\ []) do
    opts = Keyword.put_new(opts, :parsers, [Plug.Parsers.URLENCODED, Plug.Parsers.MULTIPART])
    Plug.Parsers.call(conn, Plug.Parsers.init(opts))
  end

  test "raises when no parsers is given" do
    assert_raise ArgumentError, fn ->
      parse(conn(:post, "/"), parsers: nil)
    end
  end

  test "parses query string information" do
    conn = parse(conn(:post, "/?foo=bar"))
    assert conn.params["foo"] == "bar"
    assert conn.body_params == %{}
    assert conn.query_params["foo"] == "bar"
  end

  test "keeps existing body params" do
    conn = conn(:post, "/?foo=bar")
    conn = parse(%{conn | body_params: %{"foo" => "baz"}, params: %{"foo" => "baz"}})
    assert conn.params["foo"] == "baz"
    assert conn.body_params["foo"] == "baz"
    assert conn.query_params["foo"] == "bar"
  end

  test "ignore bodies unless post/put/match/delete" do
    conn = conn(:get, "/?foo=bar", "foo=baz")
           |> put_req_header("content-type", "application/x-www-form-urlencoded")
           |> parse()
    assert conn.params["foo"] == "bar"
    assert conn.body_params == %{}
    assert conn.query_params["foo"] == "bar"
  end

  test "parses url encoded bodies" do
    conn = conn(:post, "/?foo=bar", "foo=baz")
           |> put_req_header("content-type", "application/x-www-form-urlencoded")
           |> parse()
    assert conn.params["foo"] == "baz"
  end

  test "parses multipart bodies" do
    conn = parse(conn(:post, "/?foo=bar"))
    assert conn.params == %{"foo" => "bar"}

    conn = parse(conn(:post, "/?foo=bar", [foo: "baz"]))
    assert conn.params == %{"foo" => "baz"}
  end

  test "raises on invalid url encoded" do
    assert_raise Plug.Parsers.BadEncodingError, 
                 "invalid UTF-8 on urlencoded body, got byte 139", fn ->
      conn(:post, "/foo", "a=" <> <<139>>)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse()
    end
  end

  test "raises on too large bodies" do
    exception = assert_raise Plug.Parsers.RequestTooLargeError,
                             ~r/the request is too large/, fn ->
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> parse(length: 5)
    end
    assert Plug.Exception.status(exception) == 413
  end

  test "raises when request cannot be processed" do
    exception = assert_raise Plug.Parsers.UnsupportedMediaTypeError,
                             "unsupported media type text/plain", fn ->
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> parse()
    end
    assert Plug.Exception.status(exception) == 415
  end

  test "raises when request cannot be processed and if mime range not accepted" do
    exception = assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "application/json")
      |> parse(pass: ["text/plain", "text/*"])
    end
    assert Plug.Exception.status(exception) == 415
  end

  test "does not raise when request cannot be processed if accepts all mimes" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> parse(pass: ["*/*"])
    assert conn.params["foo"] == "bar"
  end

  test "does not raise when request cannot be processed if mime accepted" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> parse(pass: ["text/plain", "application/json"])
    assert conn.params["foo"] == "bar"

    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "application/json")
      |> parse(pass: ["text/plain", "application/json"])
    assert conn.params["foo"] == "bar"
  end

  test "does not raise when request cannot be processed if accepts mime range" do
    conn =
      conn(:post, "/?foo=bar", "foo=baz")
      |> put_req_header("content-type", "text/plain")
      |> parse(pass: ["text/plain", "text/*"])
    assert conn.params["foo"] == "bar"
  end
end
