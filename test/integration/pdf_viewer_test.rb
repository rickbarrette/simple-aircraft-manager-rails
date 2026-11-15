require "test_helper"

# PDFs in the document viewer: drawn with PDF.js on phones (Android shows
# nothing in a frame), the browser's own viewer in a frame elsewhere.
class PdfViewerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner)
    @doc = @a.documents.create!(name: "POH", doc_type: "OTHER")
    @doc.pages.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "poh.pdf", content_type: "application/pdf")
  end

  test "a PDF page hands the viewer its file, the PDF.js folder and the frame" do
    sign_in @owner
    get aircraft_document_path(@a, @doc)
    assert_response :success
    assert_select "[data-controller=pdf-viewer][data-pdf-viewer-pdfjs-value=?]", Rails.application.config.x.pdfjs_path do
      assert_select "[data-pdf-viewer-url-value*='/rails/active_storage/blobs/']"
      assert_select "template[data-pdf-viewer-target=frame]"
      assert_select "[data-pdf-viewer-target=status]", text: "Loading the PDF…"
      assert_select "noscript"
    end
    assert_includes response.body, "<iframe src="
  end

  test "uploaded files say they take ranges, so only the pages looked at are fetched" do
    sign_in @owner
    get rails_blob_path(@doc.pages.first, disposition: :inline)
    file = response.location
    get file
    assert_response :success
    assert_equal "bytes", response.headers["Accept-Ranges"]
    get file, headers: { "Range" => "bytes=0-3" }
    assert_response :partial_content
    assert_equal "%PDF", response.body
  end

  test "the PDF.js files it loads by name are there" do
    dir = Rails.public_path.join(Rails.application.config.x.pdfjs_path.delete_prefix("/"))
    %w[pdf.min.mjs pdf.worker.min.mjs wasm/jbig2.wasm wasm/openjpeg.wasm wasm/openjpeg_nowasm_fallback.js wasm/qcms_bg.wasm
       standard_fonts/LiberationSans-Regular.ttf iccs/CGATS001Compat-v2-micro.icc LICENSE].each do |file|
      assert dir.join(file).file?, "missing #{file}"
    end
  end
end
