require "test_helper"

# Requests no form sends, found by fuzzing: each used to be a server error.
class MalformedInputTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner)
    sign_in @owner
  end

  test "a page in a format it doesn't have is 'not acceptable', not an error" do
    %w[pdf json csv zip xml].each do |ext|
      get "/aircraft/#{@a.id}/report.#{ext}"
      assert_response :not_acceptable, ext
    end
  end

  test "parts can't be made into a loop, and an existing loop doesn't break the pages" do
    engine = @a.components.create!(component_type: ComponentType.create!(name: "Engine"), manufacturer: "L", model: "O-320", date_in_service: Date.current)
    mag = @a.components.create!(component_type: ComponentType.create!(name: "Magneto"), manufacturer: "S", model: "4370", date_in_service: Date.current, parent_component: engine)
    patch aircraft_component_path(@a, engine), params: { component: { parent_component_id: mag.id } }
    assert_response :unprocessable_entity
    assert_nil engine.reload.parent_component_id

    engine.update_column(:parent_component_id, mag.id) # as if made before the check existed
    assert_equal [ mag.id ], engine.reload.ancestor_ids
    assert_equal [ mag.id ], engine.descendant_ids
    get new_aircraft_logbook_entry_path(@a)
    assert_response :success
  end

  test "a link to a record that doesn't exist is a validation error" do
    part = @a.components.create!(component_type: ComponentType.create!(name: "Alternator"), manufacturer: "P", model: "ALX", date_in_service: Date.current)
    patch aircraft_component_path(@a, part), params: { component: { parent_component_id: 999_999 } }
    assert_response :unprocessable_entity
  end

  test "a blank required checkbox or number takes its default" do
    post aircraft_notes_path(@a), params: { aircraft_note: { text: "Blank public", public: "" } }
    assert_equal false, @a.notes.last.public
  end

  test "text where a file belongs, or a tampered upload reference, is turned away politely" do
    post import_aircraft_oil_analyses_path(@a), params: { report: "not a file" }
    assert_redirected_to new_aircraft_oil_analysis_path(@a)
    post aircraft_imports_path, params: { archive: "not a file" }
    assert_redirected_to new_aircraft_import_path
    post aircraft_logbook_imports_path(@a), params: { pages: [ "not a file" ] }
    assert_redirected_to new_aircraft_logbook_import_path(@a)

    post aircraft_squawks_path(@a), params: { squawk: { issue_reported: "Leak", attachments: [ "eyJfcmFpbHMiOnt9fQ==--forged" ] } }
    assert_response :redirect
    assert_equal "Something in that form couldn't be saved. Check what you entered and try again.", flash[:alert]
  end

  test "a null byte is refused up front" do
    post aircraft_notes_path(@a), params: { aircraft_note: { text: "a\u0000b" } }
    assert_response :bad_request
    assert_equal 0, @a.notes.count
  end

  test "a number too big to store is turned away politely" do
    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    template = LogbookTemplate.create!(name: "T", log_type: "AC", entry_type: "MAINTENANCE", text: "x")
    patch admin_logbook_template_path(template), params: { logbook_template: { position: "9" * 40 } }
    assert_response :redirect
    assert_match "couldn't be saved", flash[:alert]
  end

  test "a rejected photo shows the form's error, not a server error" do
    patch aircraft_path(@a), params: { aircraft: { picture: Rack::Test::UploadedFile.new(StringIO.new("<html>not a photo</html>"), "text/html", original_filename: "photo.html") } }
    assert_response :unprocessable_entity
    patch aircraft_path(@a), params: { aircraft: { picture: Rack::Test::UploadedFile.new(StringIO.new(""), "image/jpeg", original_filename: "empty.jpg") } }
    assert_response :unprocessable_entity
  end

  test "an image that can't be read is shown as the file, never resized" do
    @a.picture.attach(io: StringIO.new("GIF89a not really"), filename: "broken.gif", content_type: "image/gif")
    @a.picture.blob.update!(metadata: { identified: true, analyzed: true }) # analysis found no dimensions
    assert_kind_of ActiveStorage::Attached::One, @a.picture_for(:thumb)
    get aircraft_path(@a)
    assert_response :success
    assert_select "img[src*='/representations/']", 0
  end

  test "if resizing a photo fails anyway, the original is sent instead of an error" do
    @a.picture.attach(io: StringIO.new("GIF89a not really"), filename: "broken.gif", content_type: "image/gif")
    get url_for(@a.picture.variant(:thumb))
    assert_response :redirect
    assert_match %r{/rails/active_storage/blobs/redirect/}, response.location
  end
end
