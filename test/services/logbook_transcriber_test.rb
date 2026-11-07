require "test_helper"

class LogbookTranscriberTest < ActiveSupport::TestCase
  Message = Struct.new(:stop_reason, :content, :model)
  Text = Struct.new(:type, :text)

  def client_returning(message)
    Class.new do
      define_method(:beta) { self }
      define_method(:messages) { self }
      define_method(:stream) { |**| Struct.new(:accumulated_message).new(message) }
    end.new
  end

  def transcribe(message) = LogbookTranscriber.new(client: client_returning(message)).transcribe([ { data: "x", media_type: "image/png" } ])

  test "reads the structured answer" do
    json = { entries: [ { "text" => "Annual" } ], non_logbook_pages: [ 2 ], unparseable_pages: [] }.to_json
    result = transcribe(Message.new(:end_turn, [ Text.new(:thinking, ""), Text.new(:text, json) ], "claude-opus-5-5"))
    assert_equal [ { "text" => "Annual" } ], result.entries
    assert_equal [ 2 ], result.non_logbook_pages
  end

  test "turns refusals, truncation and bad JSON into clear errors" do
    { refusal: "declined", max_tokens: "too long to finish" }.each do |reason, message|
      error = assert_raises(LogbookTranscriber::Error) { transcribe(Message.new(reason, [], "m")) }
      assert_match message, error.message
    end
    error = assert_raises(LogbookTranscriber::Error) { transcribe(Message.new(:end_turn, [ Text.new(:text, "{nope") ], "m")) }
    assert_match "wasn't valid JSON", error.message
  end
end
