require "test_helper"

class AdminSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@example.com", admin: true)
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner)
  end

  def pdf(bytes) = { io: StringIO.new("%PDF".ljust(bytes, "x")), filename: "big.pdf", content_type: "application/pdf" }

  test "only admins change settings; bad values are refused" do
    sign_in @owner
    get edit_admin_settings_path
    assert_redirected_to root_path
    patch admin_settings_path, params: { settings: { max_upload_mb: 500 } }
    assert_equal 50, Setting.max_upload_mb

    sign_in @admin
    get root_path
    assert_select "a[href='#{edit_admin_settings_path}']", text: "Settings"
    get edit_admin_settings_path
    assert_select "input[name='settings[max_upload_mb]'][value='50'][max='1024']"

    [ "0", "2000", "abc", "" ].each do |bad|
      patch admin_settings_path, params: { settings: { max_upload_mb: bad } }
      assert_response :unprocessable_entity
      assert_includes response.body, "must be a whole number from 1 to 1024"
    end
    assert_equal 50, Setting.max_upload_mb

    patch admin_settings_path, params: { settings: { max_upload_mb: "200" } }
    assert_redirected_to edit_admin_settings_path
    assert_equal [ 200, 200.megabytes ], [ Setting.max_upload_mb, Setting.max_upload_bytes ]
    get admin_about_path
    assert_includes response.body, "200 MB per file"
  end

  test "the limit applies to saved files, direct uploads and the upload pages" do
    Setting.update_integers("max_upload_mb" => "1")
    doc = @a.documents.new(name: "Scan", doc_type: "OTHER", pages: [ pdf(1.megabyte + 1) ])
    refute doc.valid?
    assert_includes doc.errors.full_messages.to_sentence, "big.pdf is over the 1 MB upload limit"
    assert @a.documents.new(name: "Scan", doc_type: "OTHER", pages: [ pdf(1.megabyte) ]).valid?

    sign_in @owner
    post "/rails/active_storage/direct_uploads", as: :json, params: { blob: {
      filename: "big.pdf", byte_size: 2.megabytes, checksum: "Q2hlY2tzdW0=", content_type: "application/pdf" } }
    assert_response :unprocessable_entity
    assert_equal "big.pdf is over the 1 MB upload limit", response.parsed_body["error"]

    get new_bulk_aircraft_documents_path(@a)
    assert_select "form[data-bulk-upload-max-bytes-value='#{1.megabyte}']"
    assert_includes response.body, "up to 1 MB each"
    get new_aircraft_squawk_path(@a)
    assert_includes response.body, "up to 1 MB each"

    Setting.update_integers("max_upload_mb" => "100") # raising it lets a 60 MB-class file through
    assert @a.documents.new(name: "Scan", doc_type: "OTHER", pages: [ pdf(60.megabytes) ]).valid?
  end
end
