require "test_helper"

# Aircraft with a separate avionics logbook file their radio, transponder
# and autopilot work under it.
class AvionicsLogbookTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    sign_in @owner
  end

  test "an entry can be written to the avionics logbook and the list filtered to it" do
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: { date: "2026-10-01", log_type: "AVIONICS", entry_type: "MAINTENANCE",
                                                                       text: "Replaced Comm 2 radio; operational check normal." } }
    entry = @a.logbook_entries.sole
    assert_equal "AVIONICS", entry.log_type
    @a.logbook_entries.create!(date: Date.new(2026, 10, 2), log_type: "AC", entry_type: "MAINTENANCE", text: "Lubricated door hinges.")

    get aircraft_logbook_entries_path(@a, log_type: "AVIONICS")
    assert_response :success
    assert_includes response.body, "Replaced Comm 2 radio"
    assert_not_includes response.body, "Lubricated door hinges"
    assert_includes response.body, ">Avionics<"
  end

  test "logbook transcription and the drafts API know the avionics logbook" do
    assert LogbookEntry::LOG_TYPES.key?("AVIONICS")
    assert_includes JSON.parse(Rails.root.join("app/services/logbook_transcriber/schema.json").read).to_s, "AVIONICS"
  end
end
