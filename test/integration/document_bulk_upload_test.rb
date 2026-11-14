require "test_helper"

class DocumentBulkUploadTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot)
  end

  def upload(name, body = "page", type = "image/jpeg")
    Rack::Test::UploadedFile.new(StringIO.new(body), type, original_filename: name)
  end

  def direct_blob(name, type = "image/jpeg")
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("bytes"), filename: name, content_type: type)
  end

  test "collections are collapsed on the documents page, with their document count" do
    sign_in @owner
    @a.document_collections.create!(name: "Engine logbook").documents.create!(aircraft: @a, name: "Scan", doc_type: "LOG")
    @a.documents.create!(name: "Loose receipt", doc_type: "INVOICE")
    get aircraft_documents_path(@a)
    assert_select "details.document-collection", 2
    assert_select "details.document-collection[open]", 0 # collapsed until clicked
    assert_select "details.document-collection summary h2", text: /Engine logbook\s*\(1\)/
    assert_select "details.document-collection summary h2", text: /Uncollected\s*\(1\)/
    assert_select "details.document-collection a", text: "Scan" # still in the page, just closed
  end

  test "owner sees the bulk page; pilots and outsiders can't use it" do
    sign_in @owner
    get aircraft_documents_path(@a)
    assert_select "a[href='#{new_bulk_aircraft_documents_path(@a)}']", text: "Upload several files"
    get new_bulk_aircraft_documents_path(@a)
    assert_response :success
    assert_select "form[data-controller='bulk-upload'][data-bulk-upload-url-value='/rails/active_storage/direct_uploads']"
    assert_select "input[type=file][name='files[]'][multiple]"
    assert_select "input[type=file][webkitdirectory]"

    sign_in @pilot
    post bulk_aircraft_documents_path(@a), params: { files: [ upload("a.jpg") ] }
    assert_redirected_to aircraft_path(@a)
    assert_equal 0, Document.count

    sign_in create_user
    get new_bulk_aircraft_documents_path(@a)
    assert_response :not_found
  end

  test "plain uploads (no JavaScript) become one document per file, named after the file" do
    sign_in @owner
    col = @a.document_collections.create!(name: "Annual", visibility: "private")
    post bulk_aircraft_documents_path(@a), params: {
      files: [ upload("weight_and_balance.pdf", "%PDF", "application/pdf"), upload("Form 337.jpg") ],
      doc_type: "ALTER", visibility: "maintenance", document_collection_id: col.id
    }
    assert_redirected_to aircraft_documents_path(@a)
    assert_equal "2 documents uploaded.", flash[:notice]
    docs = @a.documents.order(:name)
    assert_equal [ "Form 337", "weight and balance" ], docs.map(&:name)
    assert docs.all? { _1.doc_type == "ALTER" && _1.visibility == "maintenance" && _1.document_collection == col && _1.pages.size == 1 }
    assert_equal "2 documents uploaded", @a.events.last.event_name
  end

  test "direct uploads: same name combines pages in order; a new collection is made" do
    sign_in @owner
    blobs = %w[p1.jpg p2.jpg receipt.jpg].map { direct_blob(_1) }
    post bulk_aircraft_documents_path(@a), params: {
      files: blobs.map(&:signed_id), names: [ "Engine log 1", "Engine log 1", "Prop overhaul receipt" ],
      new_collection: "Logbooks", doc_type: "LOG"
    }
    assert_redirected_to aircraft_documents_path(@a)
    col = @a.document_collections.find_by!(name: "Logbooks")
    assert_equal "private", col.visibility
    log = col.documents.find_by!(name: "Engine log 1")
    assert_equal %w[p1.jpg p2.jpg], log.pages.map { _1.filename.to_s }
    assert_nil log.visibility
    assert_equal 1, col.documents.find_by!(name: "Prop overhaul receipt").pages.size
  end

  test "already-attached blobs and bad files are refused; partial success is reported" do
    sign_in @owner
    other = @a.documents.create!(name: "Existing", doc_type: "OTHER", pages: [ upload("x.jpg") ])
    good = direct_blob("good.jpg")
    bad = direct_blob("tool.exe", "application/x-msdownload")
    post bulk_aircraft_documents_path(@a), params: { files: [ other.pages.first.blob.signed_id, good.signed_id, bad.signed_id ] }
    assert_redirected_to aircraft_documents_path(@a)
    assert_equal "1 document uploaded.", flash[:notice]
    assert_match(/file 1 \(upload expired/, flash[:alert])
    assert_match(/tool \(Pages tool.exe is not an allowed file type\)/, flash[:alert])
    assert_equal [ "Existing", "good" ], @a.documents.order(:name).map(&:name)
    assert_equal 1, other.reload.pages.size
  end

  test "nothing valid re-renders the form and drops the new collection" do
    sign_in @owner
    post bulk_aircraft_documents_path(@a), params: { new_collection: "Junk" }
    assert_response :unprocessable_entity
    assert_includes response.body, "Choose some files to upload."

    post bulk_aircraft_documents_path(@a), params: { files: [ upload("a.exe", "MZ", "application/x-msdownload") ], new_collection: "Junk" }
    assert_response :unprocessable_entity
    assert_includes response.body, "Nothing was uploaded"
    assert_select "input[name=new_collection][value=Junk]"
    assert_equal 0, @a.document_collections.count
  end

  test "direct-upload endpoint needs a session and checks type and size first" do
    blob = ->(filename, type, size = 10) { { blob: { filename: filename, byte_size: size, checksum: "Q2hlY2tzdW0=", content_type: type } } }
    post "/rails/active_storage/direct_uploads", params: blob.("a.jpg", "image/jpeg"), as: :json
    assert_redirected_to new_session_path
    assert_equal 0, ActiveStorage::Blob.count

    sign_in @owner
    post "/rails/active_storage/direct_uploads", params: blob.("a.exe", "application/x-msdownload"), as: :json
    assert_response :unprocessable_entity
    assert_match "is not an allowed file type", response.parsed_body["error"]
    post "/rails/active_storage/direct_uploads", params: blob.("big.pdf", "application/pdf", 51.megabytes), as: :json
    assert_response :unprocessable_entity

    post "/rails/active_storage/direct_uploads", params: blob.("scan.png", ""), as: :json
    assert_response :success
    assert_equal "image/png", ActiveStorage::Blob.last.content_type
    assert response.parsed_body["signed_id"].present?
  end

  test "the same file direct-uploaded twice is stored once on disk" do
    sign_in @owner
    body = "%PDF-1.4 identical scan"
    ids = 2.times.map do |i|
      post "/rails/active_storage/direct_uploads", as: :json, params: { blob: {
        filename: "scan#{i}.pdf", byte_size: body.bytesize, checksum: OpenSSL::Digest::MD5.base64digest(body), content_type: "application/pdf" } }
      signed_id, upload = response.parsed_body.values_at("signed_id", "direct_upload")
      put URI(upload["url"]).request_uri, params: body, headers: upload["headers"]
      assert_response :no_content
      signed_id
    end
    post bulk_aircraft_documents_path(@a), params: { files: ids }
    assert_redirected_to aircraft_documents_path(@a)
    paths = @a.documents.order(:name).map { ActiveStorage::Blob.service.path_for(_1.pages.first.key) }
    assert_equal 2, paths.size
    assert_equal File.stat(paths[0]).ino, File.stat(paths[1]).ino
    assert_equal %w[scan0 scan1], @a.documents.order(:name).map(&:name)
  end
end
