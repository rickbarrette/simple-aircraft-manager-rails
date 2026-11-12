require "test_helper"

# Basics every page shares: language, skip link, alt text, and the date format.
class AccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    sign_in @owner
  end

  test "pages declare their language and let keyboard users skip to the content" do
    [ root_path, aircraft_path(@a), aircraft_logbook_entries_path(@a), help_path ].each do |path|
      get path
      assert_select "html[lang=en]"
      assert_select "a.skip-link[href='#main']", text: "Skip to content"
      assert_select "main#main"
      assert_select "img:not([alt])", 0, "#{path}: every image has alt text"
    end
  end

  test "dates read the same way everywhere" do
    @a.logbook_entries.create!(date: Date.new(2026, 11, 8), entry_type: "MAINTENANCE", text: "Changed oil", aircraft_hours_at_entry: 1000)
    get aircraft_logbook_entries_path(@a)
    assert_includes response.body, "Nov 8, 2026"
    refute_includes response.body, "November 08, 2026"
  end
end
