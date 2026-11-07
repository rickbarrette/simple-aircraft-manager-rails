require "test_helper"

class NotesMarkdownTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @a = create_aircraft(owner: @owner, pilot: @pilot)
  end

  test "notes render Markdown on the notes tab, overview and share links" do
    note = @a.notes.create!(text: "## Hangar\n**Code** 1234\n\n- [ ] Return key", public: true, user: @owner)
    sign_in @pilot
    get aircraft_notes_path(@a)
    assert_select ".markdown h2", "Hangar"
    assert_select ".markdown strong", "Code"
    get aircraft_path(@a)
    assert_includes response.body, "Hangar Code 1234 Return key"

    token = @a.share_tokens.create!(privilege: "status")
    get shared_path(token.token)
    assert_select ".markdown strong", "Code"
    assert note
  end

  test "the editor has Write/Preview tabs and the preview renders server-side" do
    sign_in @pilot # pilots can add notes, so they can preview them too
    get new_aircraft_note_path(@a)
    assert_select "[data-controller=markdown-editor][data-markdown-editor-url-value='#{preview_aircraft_notes_path(@a)}']"
    assert_select "textarea[name='aircraft_note[text]'][data-markdown-editor-target=input]"
    post preview_aircraft_notes_path(@a), params: { text: "*hi* <script>x</script>" }
    assert_response :success
    assert_includes response.body, "<em>hi</em>"
    refute_includes response.body, "<script"

    sign_in create_user
    post preview_aircraft_notes_path(@a), params: { text: "x" }
    assert_response :not_found
  end
end
